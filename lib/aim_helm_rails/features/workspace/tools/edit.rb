module AimHelmRails
  module Features
    class Workspace
      class Tools
        module Edit
          SCHEMA = AimHelm::Schema.define do
            required(:path).filled(:string)
            required(:old_string).filled(:string)
            required(:new_string).value(:string)
            optional(:replace_all).filled(:bool)
          end

          private

          def edit_description
            "Replace an exact snippet copied without displayed path or line prefixes in #{purpose}"
          end

          def edit(adapter, arguments)
            path = document_path(arguments)
            result = perform_edit(adapter, path, arguments)
            AimHelm::Tool::Result.success(
              content: "Replaced #{result.count} occurrence(s) in #{name}/#{path}",
            )
          rescue EditError => e
            AimHelm::Tool::Result.failure(content: "#{name}_edit failed: #{e.message}")
          rescue ConflictError
            AimHelm::Tool::Result.failure(content: "#{name}/#{path} kept changing; read it again")
          end

          def perform_edit(adapter, path, arguments)
            Workspace::Edit.call(
              adapter,
              path:,
              old_string: arguments.fetch("old_string"),
              new_string: arguments.fetch("new_string"),
              replace_all: arguments["replace_all"] == true,
            )
          end
        end
      end
    end
  end
end
