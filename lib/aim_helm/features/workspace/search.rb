# frozen_string_literal: true

module AimHelm
  module Features
    class Workspace
      class Search
        MAX_CHARACTERS = 20_000
        MAX_CONTEXT_LINES = 20
        MAX_LINE_CHARACTERS = 2_000
        MAX_MATCHES = 100

        Context = Data.define(:before, :after)
        class MissingDocument < StandardError; end

        class << self
          def call(adapter, query, options = {})
            validate_scope(options)
            selected, total = select_matches(
              documents(adapter, options), query, match_limit(options[:max_matches])
            )
            return "No matches for #{query.inspect}." if total.zero?

            render(selected, query, context(options), total)
          end

          private

          def select_matches(documents, query, max_matches)
            selected = {}
            total = 0
            remaining = max_matches

            documents.each do |document_path, lines|
              hits = lines.each_index.select { lines[it].include?(query) }
              total += hits.length
              selected[document_path] = [lines, hits.first(remaining)] if remaining.positive?
              remaining -= [hits.length, remaining].min
            end

            [selected, total]
          end

          def documents(adapter, options)
            path = options[:path]
            prefix = options[:prefix]
            paths = path ? [path] : adapter.list(prefix)

            paths.to_h do
              content = adapter.read(it)
              raise MissingDocument, it if path && !content

              [it, content&.lines || []]
            end
          end

          def validate_scope(options)
            return unless options[:path] && options[:prefix]

            raise ArgumentError,
                  "pass path or prefix, not both"
          end

          def context(options)
            Context.new(
              before: (options[:before] || 2).clamp(0, MAX_CONTEXT_LINES),
              after: (options[:after] || 2).clamp(0, MAX_CONTEXT_LINES),
            )
          end

          def match_limit(value) = (value || 20).clamp(1, MAX_MATCHES)

          def render(selected, query, context, total)
            groups = render_groups(selected, query, context)
            shown = selected.sum { it.last.last.length }
            notice = "[showing first #{shown} of #{total} matching lines]" if shown < total

            truncate([groups, notice].compact.join("\n"))
          end

          def render_groups(selected, query, context)
            selected.flat_map do |path, (lines, hits)|
              render_document(path, lines, hits, query, context)
            end.join("\n--\n")
          end

          def render_document(path, lines, hits, query, context)
            hit_lookup = hits.to_h { [it, true] }

            ranges(hits, lines.length, context).map do
              render_range(path, lines, hit_lookup, query, it)
            end
          end

          def render_range(path, lines, hit_lookup, query, range)
            range.map do
              format_line(path, it, lines[it], query:, matching: hit_lookup.key?(it))
            end.join("\n")
          end

          def ranges(hits, line_count, context)
            raw_ranges = hits.map do
              [it - context.before, 0].max..[it + context.after, line_count - 1].min
            end
            raw_ranges.each_with_object([]) { |range, merged| merge_range(range, merged) }
          end

          def merge_range(range, merged)
            return merged << range unless merged.last && range.begin <= merged.last.end + 1

            merged[-1] = merged.last.begin..[merged.last.end, range.end].max
          end

          def format_line(path, index, line, query:, matching:)
            separator = matching ? ":" : "-"
            text = line.delete_suffix("\n").delete_suffix("\r")
            text = clip(text, query: matching ? query : nil)
            "#{path}#{separator}#{index + 1}#{separator}#{text}"
          end

          def clip(text, query:)
            return text if text.length <= MAX_LINE_CHARACTERS

            start = query ? [text.index(query) - (MAX_LINE_CHARACTERS / 2), 0].max : 0
            start = [start, text.length - MAX_LINE_CHARACTERS].min
            excerpt = text[start, MAX_LINE_CHARACTERS]
            "#{"…" if start.positive?}#{excerpt}#{"…" if start + excerpt.length < text.length}"
          end

          def truncate(content)
            return content if content.length <= MAX_CHARACTERS

            notice = "\n[truncated at #{MAX_CHARACTERS} chars; narrow path, prefix, or context]"
            cut = content[0, MAX_CHARACTERS - notice.length]
            cut = cut[0..(cut.rindex("\n") || -1)]
            "#{cut}#{notice}"
          end
        end
      end
    end
  end
end
