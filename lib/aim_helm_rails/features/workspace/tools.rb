module AimHelmRails
  module Features
    class Workspace
      # One AimHelm::Tool per operation of a mount. Each operation module supplies its SCHEMA,
      # `<operation>_description`, and `<operation>(adapter, arguments)` handler.
      class Tools
        OPERATIONS = %i[list read write edit].freeze

        include List
        include Read
        include Write
        include Edit

        def initialize(workspace, name:, purpose:, only:)
          @workspace = workspace
          @name = name.to_s
          @purpose = purpose.to_s
          @only = only.map(&:to_sym)

          unknown = @only - OPERATIONS
          raise ArgumentError, "unknown workspace operations: #{unknown.join(", ")}" if unknown.any?
        end

        def to_a = @only.map { tool(it) }

        private

        attr_reader :workspace, :name, :purpose

        def tool(operation)
          AimHelm::Tool.define(
            "#{name}_#{operation}",
            send(:"#{operation}_description"),
            identifier: "workspace/#{name}/#{operation}",
            schema: Tools.const_get(operation.to_s.camelize)::SCHEMA,
          ) do |arguments, context|
            send(operation, workspace.adapter_for(context), arguments)
          rescue InvalidPath, ReadOnly => e
            AimHelm::Tool::Result.failure(content: "#{name}_#{operation}: #{e.message}")
          end
        end

        # Paths are shown as <mount>/<path>, the form the shell takes; the mount prefix is optional here.
        def document_path(arguments)
          Workspace.path!(arguments.fetch("path").delete_prefix("#{name}/"))
        end

        def missing(path)
          AimHelm::Tool::Result.failure(
            content: "No document at #{name}/#{path}. Use #{name}_list to see paths.",
          )
        end
      end
    end
  end
end
