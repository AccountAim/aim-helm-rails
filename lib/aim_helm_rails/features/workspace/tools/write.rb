module AimHelmRails
  module Features
    class Workspace
      class Tools
        module Write
          SCHEMA = AimHelm::Schema.define do
            required(:path).filled(:string)
            required(:content).value(:string)
          end

          private

          def write_description = "Create or fully overwrite a document in #{purpose}"

          def write(adapter, arguments)
            path = document_path(arguments)
            content = arguments.fetch("content")
            adapter.write(path, content)

            AimHelm::Tool::Result.success(content: "Wrote #{name}/#{path}, #{content.length} chars")
          end
        end
      end
    end
  end
end
