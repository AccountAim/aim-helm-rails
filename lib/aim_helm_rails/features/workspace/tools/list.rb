module AimHelmRails
  module Features
    class Workspace
      class Tools
        module List
          SCHEMA = AimHelm::Schema.define do
            optional(:prefix).maybe(:string)
            optional(:text)
              .maybe(:string)
              .documentation(description: "Only paths whose content or path contains this text.")
          end

          private

          def list_description
            <<~TEXT.squish
              List documents in #{purpose} with their line count and size, optionally only
              those mentioning a text
            TEXT
          end

          # knowledge_base/app/platform.md  61 lines, 4.1 KB
          def list(adapter, arguments)
            entries = adapter.entries(arguments["prefix"], text: arguments["text"])
            return AimHelm::Tool::Result.success(content: "No documents found.") if entries.empty?

            lines = entries.map do |path, bytes, count|
              size = ActiveSupport::NumberHelper.number_to_human_size(bytes)
              "#{name}/#{path}  #{count} lines, #{size}"
            end
            AimHelm::Tool::Result.success(content: lines.join("\n"))
          end
        end
      end
    end
  end
end
