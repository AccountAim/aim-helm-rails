# frozen_string_literal: true

module AimHelm
  module Features
    class Workspace
      class Window
        MAX_CHARACTERS = 20_000

        def self.call(content, offset: nil, limit: nil)
          lines = content.lines
          first, last = bounds(lines, offset:, limit:)
          numbered = (first..last).map { "#{it}: #{lines[it - 1]}" }.join
          suffix =
            if last < lines.length || first > 1
              "\n[showing lines #{first}-#{last} of #{lines.length}]"
            else
              ""
            end

          truncate(numbered) || "#{numbered}#{suffix}"
        end

        def self.bounds(lines, offset:, limit:)
          first = [offset || 1, 1].max
          count = [limit || lines.length, 1].max
          last = [first + count - 1, lines.length].min
          [first, last]
        end

        def self.truncate(numbered)
          return if numbered.length <= MAX_CHARACTERS

          cut = numbered[0, MAX_CHARACTERS]
          cut = cut[0..(cut.rindex("\n") || -1)]
          "#{cut}\n[truncated at #{MAX_CHARACTERS} chars; use offset/limit to read more]"
        end

        private_class_method :bounds, :truncate
      end
    end
  end
end
