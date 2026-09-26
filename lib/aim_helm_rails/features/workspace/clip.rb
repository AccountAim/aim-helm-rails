module AimHelmRails
  module Features
    class Workspace
      # The head of a long text, whole lines within a line and byte budget, then one trailer
      # saying how to reach the rest through the shell at `at`, the path where the full text
      # lives. Every place the host hands an agent a long text clips it this way.
      class Clip
        LINES = 60
        BYTES = 4_000

        def self.call(text, at:, offset: 1, limit: LINES, numbered: false)
          lines = text.lines
          total = lines.length
          first = [offset, 1].max
          return beyond(total) if first > total

          shown, cut = fit(render(lines, first, limit, numbered))
          last = first + shown.length - 1
          return shown.join if !cut && first == 1 && last >= total

          "#{shown.join}\n#{trailer(at, first, last, total, cut)}"
        end

        def self.beyond(total) = "[only #{total} lines; start at or before line #{total}]"

        def self.render(lines, first, limit, numbered)
          last = [first + [limit, 1].max - 1, lines.length].min
          (first..last).map { numbered ? "#{it}: #{lines[it - 1]}" : lines[it - 1] }
        end

        # Whole lines up to the byte budget; a first line over the budget on its own is cut.
        def self.fit(lines)
          size = 0
          kept = lines.take_while { (size += it.bytesize) <= BYTES || size == it.bytesize }
          return [kept, false] unless kept.first && kept.first.bytesize > BYTES

          [["#{kept.first.byteslice(0, BYTES).scrub("")}…\n"], true]
        end

        def self.trailer(at, first, last, total, cut)
          where = "lines #{first}-#{last} of #{total}"
          where = "line #{first} cut at #{BYTES} bytes, #{total} lines in all" if cut
          path = at.delete_prefix("/")
          <<~TEXT.chomp
            [#{where}; the rest through workspace_bash with paths ["#{path}"],
            e.g. sed -n '#{last + 1},#{last + LINES}p' #{path} or rg -n -C 2 PATTERN #{path}]
          TEXT
        end

        private_class_method :beyond, :render, :fit, :trailer
      end
    end
  end
end
