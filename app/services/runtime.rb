module AimHelmRails
  module Runtime
    class << self
      # Queues a turn for the session's helmsman and returns the session; the reply arrives later over
      # the event stream. A helmsman that advances inline runs here instead, and the session comes
      # back answered.
      def run(session, prompt, actor: session.actor, tenant: session.tenant)
        authorize!(session, actor:, tenant:, action: :update)
        definition = definition_for(session)
        aim_helm_session = AimHelm.session(session.id)

        session.with_lock do
          bind_actor!(session, actor, aim_helm_session)
          dispatch(definition, aim_helm_session, prompt:, context: session.aim_helm_context)
        end

        session.reload
      end

      # Approves or denies a tool call the agent is parked on, and returns the recorded entry, or nil
      # when that same decision was already recorded. always_allow additionally saves an AllowRule so
      # the tool stops asking, and pairs only with :approve.
      # rubocop:disable-next Metrics/ParameterLists -- the decision and both identities are explicit
      def decide(session:, call_id:, verdict:, actor:, tenant:, always_allow: false)
        authorize!(session, actor:, tenant:, action: :update)
        validate_decision!(verdict, always_allow:)

        aim_helm_session = AimHelm.session(session.id)
        rule = decision_rule(aim_helm_session, call_id, actor:, tenant:) if always_allow
        attributes = { by: actor.to_gid.to_s, rule: rule&.to_gid&.to_s }

        persist_decision(aim_helm_session, call_id, verdict:, attributes:)
      end

      # Tells a session's agent something happened outside the conversation — a button click,
      # not typing. The event runs a normal turn; the transcript hides the machine-authored
      # message, so the agent's reaction reads as a continuation.
      def signal(session, event) = run(session, "<system-event>#{event}</system-event>")

      # The assistant's last words in a session, for a caller that ran a turn and wants the answer
      # rather than the transcript.
      def reply(session:, actor:, tenant:)
        authorize!(session, actor:, tenant:, action: :read)

        messages = AimHelm::Replay.messages(AimHelm.session(session.id).entries)
        messages.reverse_each.find { it.role == :assistant }&.text
      end

      # Transcript snapshot plus the session's name and status.
      def read(session:, actor:, tenant:)
        authorize!(session, actor:, tenant:, action: :read)

        aim_helm_session = AimHelm.session(session.id)
        AimHelm::Control.new(session: aim_helm_session).read.merge(
          name: session.name,
          status: aim_helm_session.status.to_s,
        )
      end

      # Cancels the live run and its subagents; the advance this queues writes the stopped terminal.
      def stop(session:, actor:, tenant:)
        authorize!(session, actor:, tenant:, action: :update)

        AimHelm.session(session.id).stop
        session.reload
      end

      # Puts a session back on the worker — recovery for a turn left pending, not a way to send input.
      def advance(session:, actor:, tenant:)
        authorize!(session, actor:, tenant:, action: :update)

        AimHelm.config.advance.call(session.id.to_s)
      end

      private

      def definition_for(session)
        definition = with_registered_tools(AimHelmRails.host.helmsman(session.helmsman).agent)
        session.setup.any? ? definition.with(**session.setup) : definition
      end

      def bind_actor!(session, actor, aim_helm_session)
        # Prime under the lock so the broadcaster thread never queries.
        HelmIntegration.cache_stream(session)

        # A running turn keeps its actor's grant.
        if aim_helm_session.pending_run_id && session.aim_helm_context.actor != actor
          raise ActiveRecord::RecordNotFound
        end

        session.update!(execution_actor_gid: actor.to_gid.to_s)
      end

      def dispatch(definition, aim_helm_session, prompt:, context:)
        if definition.advance_mode == :inline
          run_inline(definition, aim_helm_session, prompt:, context:)
        else
          definition.run(prompt, session: aim_helm_session, context:)
        end
      end

      # An inline turn has no worker to hand subagents to, so it hosts them on threads it owns and
      # closes: a specialist still working when the turn ends is dropped with it.
      def run_inline(definition, aim_helm_session, prompt:, context:)
        host = AimHelm::Subagents::ThreadHost.new(options: definition)
        hosted = aim_helm_session.new(
          config: AimHelm.config.with(advance: host.method(:advance), subagent_host: host),
        )

        host.owning(session: hosted, app: context) do
          definition.with(advance_mode: :inline).run(prompt, session: hosted, context:)
        end
      ensure
        host.close
      end

      def authorize!(session, actor:, tenant:, action:)
        raise ActiveRecord::RecordNotFound unless session.tenant == tenant

        AimHelmRails.host.authorize!(session, actor:, tenant:, action:)
      end

      def validate_decision!(verdict, always_allow:)
        allowed = %i[approve deny].include?(verdict.to_sym)
        raise ArgumentError, "unknown verdict #{verdict.inspect}" unless allowed
        return unless always_allow && verdict.to_sym != :approve

        raise ArgumentError, "only approved tools can be always allowed"
      end

      def decision_rule(aim_helm_session, call_id, actor:, tenant:)
        approval = aim_helm_session.pending_approvals.find { it.call_id == call_id }

        unless approval
          raise AimHelm::ConfigurationError,
                "no open approval for #{call_id.inspect}"
        end

        AimHelmRails::AllowRule.within(tenant).by(actor)
                               .create_or_find_by!(tool_name: approval.tool_name)
      end

      def persist_decision(aim_helm_session, call_id, verdict:, attributes:)
        return aim_helm_session.approve(call_id, **attributes) if verdict.to_sym == :approve

        aim_helm_session.deny(call_id, by: attributes.fetch(:by))
      end

      # Tools travel as registered identifiers, so a stored run record names them rather than
      # carrying a closure the next worker cannot rebuild.
      def with_registered_tools(agent)
        resolver = AimHelm.config.tools
        agent.with(tools: resolver.identifiers(agent.tools).map { resolver.resolve(it) })
      end
    end
  end
end
