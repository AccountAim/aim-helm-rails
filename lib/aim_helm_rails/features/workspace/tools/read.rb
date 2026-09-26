module AimHelmRails
  module Features
    class Workspace
      class Tools
        module Read
          SCHEMA = AimHelm::Schema.define do
            required(:path).filled(:string)
            optional(:offset).filled(:integer)
            optional(:limit).filled(:integer)
          end

          private

          def read_description
            <<~TEXT.squish
              Read the first lines of a document in #{purpose}, numbered; the rest through
              workspace_bash on the mounted path
            TEXT
          end

          def read(adapter, arguments)
            path = document_path(arguments)
            content = adapter.read(path)
            return missing(path) unless content

            window = { offset: arguments["offset"], limit: arguments["limit"] }.compact
            AimHelm::Tool::Result.success(
              content: Clip.call(content, at: "/#{name}/#{path}", numbered: true, **window),
            )
          end
        end
      end
    end
  end
end
