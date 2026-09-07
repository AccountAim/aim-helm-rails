module AimHelmRails
  module Features
    module Workspace
      ACCESS = {
        read: %i[list read search].freeze,
        write: %i[list read write edit search].freeze,
      }.freeze

      private_constant :ACCESS

      module_function

      def register(registry = AimHelmRails.host.tools)
        registry.register(*memory_tools, *knowledge_base_tools(access: :write))
      end

      def memory_tools
        AimHelm::Features::Workspace.adapter do
          execution = it.app
          Adapters::ActiveRecord
            .new(kind: :memory, actor: execution.actor, tenant: execution.tenant)
        end.tools(
          name: :memory,
          purpose: "the current user's private durable memory across conversations",
        )
      end

      def knowledge_base_tools(access: :read)
        AimHelm::Features::Workspace.adapter do
          execution = it.app
          Adapters::ActiveRecord.new(kind: :knowledge_base, tenant: execution.tenant)
        end.tools(
          name: :knowledge_base,
          purpose: "the shared durable knowledge base",
          only: ACCESS.fetch(access.to_sym),
        )
      end
    end
  end
end
