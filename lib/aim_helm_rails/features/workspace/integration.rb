module AimHelmRails
  module Features
    class Workspace
      module Integration
        ACCESS = {
          read: %i[list read].freeze,
          write: %i[list read write edit].freeze,
        }.freeze

        private_constant :ACCESS

        module_function

        # workspace_bash needs the aim-helm-bashkit gem; without it the typed tools stand alone.
        def register(registry = AimHelmRails.host.tools)
          registry.register(*memory_tools, *knowledge_base_tools(access: :write))
          registry.register(workspace_bash) if defined?(AimHelmBashkit)
        end

        def memory_tools
          Workspace.adapter { memory_store(it) }.tools(
            name: :memory,
            purpose: "the current user's private durable memory across conversations",
          )
        end

        def knowledge_base_tools(access: :read)
          Workspace.adapter { knowledge_base_store(it) }.tools(
            name: :knowledge_base,
            purpose: "the shared durable knowledge base",
            only: ACCESS.fetch(access.to_sym),
          )
        end

        # One shell with scratch as its home and the other stores mountable beside it.
        def workspace_bash
          Bash.define { |mount, context| public_send(:"#{mount}_store", context) }
        end

        # Memory follows the chat's owner, like scratch; a guest in a shared chat only reads it.
        def memory_store(context)
          execution = context.app
          store = Adapters::ActiveRecord.new(
            kind: :memory, actor: execution.owner, tenant: execution.tenant,
          )
          execution.actor == execution.owner ? store : store.readonly
        end

        def knowledge_base_store(context)
          Adapters::ActiveRecord.new(kind: :knowledge_base, tenant: context.app.tenant)
        end

        # Scratch belongs to one conversation and is keyed by its root chat, so a subagent works
        # on the same files as the chat that delegated to it.
        def scratch_store(context)
          chat_scratch(AimHelmRails::Session.find(context.session_id).root)
        end

        # One scratch store per owner, a folder per chat.
        def chat_scratch(chat)
          Adapters::ActiveRecord.new(kind: :scratch, tenant: chat.tenant, actor: chat.root.actor,
                                     root: "#{chat.root.id}/")
        end
      end
    end
  end
end
