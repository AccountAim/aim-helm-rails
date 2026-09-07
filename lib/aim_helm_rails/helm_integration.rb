module AimHelmRails
  module HelmIntegration
    BROADCAST_INTERVAL = 0.25

    module_function

    def apply
      AimHelm.configure do
        configure_runtime(it)
        configure_providers(it)
        configure_host(it)
      end
    end

    def configure_runtime(config)
      Features::Workspace.register(AimHelmRails.host.tools)
      config.logger = Rails.logger
      config.telemetry = method(:instrument)
      config.tools = AimHelmRails.host.tools
      config.authorize = method(:authorize)
      config.broadcast = method(:enqueue_broadcast)
    end

    # The base URL an SDK would take, `/v1` included. Unset or empty leaves each client on its
    # vendor default, which is how a swap to a local server is reverted.
    def configure_providers(config)
      config.provider(:anthropic, base_url: ENV["ANTHROPIC_BASE_URL"].presence)
      config.provider(:openai, base_url: ENV["OPENAI_BASE_URL"].presence)
    end

    def configure_host(config)
      config.session_model = Session
      config.subagent_host = config.store.subagent_host
      config.advance_job = AdvanceSessionJob
      config.advance = AimHelm::ActiveJob.method(:dispatch)
    end

    def instrument(event, **payload)
      ActiveSupport::Notifications.instrument("aim_helm.#{event}", payload)
    end

    def authorize(context:, tool:, **)
      rule = AllowRule.within(context.tenant).by(context.actor)
                      .find_by(tool_name: tool.identifier || tool.name)
      rule&.to_global_id&.to_s
    end

    # A delivery that knows its Turbo stream. The stream is resolved on the caller's thread: the
    # broadcaster thread must not touch the database, which transactional tests pin to the
    # example's thread.
    class StreamedDelivery < AimHelm::Events::Delivery
      attribute :stream, AimHelm::Types::String
    end

    TERMINAL_EVENTS = %i[run.completed run.failed run.stopped].freeze

    # One lookup per run: the stream is cached from the first event until the run ends.
    def enqueue_broadcast(delivery)
      session_id = delivery.session.id.to_s
      stream = streams[session_id] ||= stream_for(session_id)
      streams.delete(session_id) if TERMINAL_EVENTS.include?(delivery.event.type)
      broadcaster.call(StreamedDelivery.new(**delivery.attributes, stream:))
    end

    def streams = @streams ||= Concurrent::Map.new

    def cache_stream(session)
      streams[session.id.to_s] = "agent:#{root_session_id(session)}"
    end

    def stream_for(session_id)
      "agent:#{root_session_id(Session.find(session_id))}"
    end

    def broadcaster
      @broadcaster ||= AimHelm::Events::Coalesced.new(
        sink: method(:broadcast),
        interval: BROADCAST_INTERVAL,
      )
    end

    def broadcast(delivery)
      Turbo::StreamsChannel.broadcast_append_to(
        delivery.stream,
        # A chat's events land in its own element, so several chats can share a page.
        target: delivery.stream.sub("agent:", "agent-events-"),
        partial: "aim_helm_rails/events/subscriber",
        locals: broadcast_locals(delivery.event, session_id: delivery.session.id.to_s),
      )
    rescue StandardError => e
      report_broadcast_error(e, delivery.session.id)
    end

    def broadcast_locals(event, session_id:)
      {
        event_type: event.type,
        payload: event_payload(event),
        run_id: event.run_id,
        session_id:,
        turn_id: event.turn_id,
      }
    end

    def root_session_id(session)
      session = session.parent_session while session.parent_session_id
      session.id
    end

    def report_broadcast_error(error, session_id)
      Rails.error.report(
        error,
        handled: true,
        severity: :warning,
        context: { agent_session_id: session_id },
      )
    end

    def event_payload(event)
      fields = AimHelm::Event::FIELDS - %i[run_id session_id turn_id]
      payload = event.payload.merge(event.to_h.slice(*fields).compact.stringify_keys)

      if %i[resource.render.inline resource.render.aside].include?(event.type)
        return Resource.presentation(payload, key: event.call_id).stringify_keys
      end

      usage = priced_usage(event.message)
      usage ? payload.merge("usage" => usage) : payload
    end

    def priced_usage(message)
      return unless message

      AimHelm::Session::Usage::Step.live_item(message, catalog: AimHelm.models)
    end
  end
end
