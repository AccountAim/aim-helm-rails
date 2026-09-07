module AimHelmRails
  class Session
    class History
      class UserMessages
        # Visibility is opt-in: only what the person typed — wrapped in <user-message> at
        # submit — renders in the transcript. Machine-authored content (signals, system
        # events) carries no tag and stays in the model's history alone.
        TYPED = %r{<user-message>(.*?)</user-message>}m

        def initialize(entries)
          @entries = entries
        end

        def title = visible_texts.first&.truncate(60) || "Untitled"
        def count = visible_texts.count

        def text(entry)
          content = decoded(entry)&.fetch(:content)
          content&.scan(TYPED)&.join("\n\n")
        end

        def attachments(entry)
          return [] unless entry

          Attachments.resolve(decoded(entry).fetch(:gids), session: entry.session)
        end

        private

        attr_reader :entries

        def decoded(entry)
          return unless entry

          Attachments.decode(raw_text(entry))
        end

        def raw_text(entry)
          covered = entry.payload["covers_through_entry_id"]
          return entry_text(entry) unless covered

          queued_entries(entry, covered).map { entry_text(it) }.join("\n\n")
        end

        def entry_text(entry)
          entry.payload.fetch("content").filter_map do
            it["text"] if it.fetch("type") == "text"
          end.join
        end

        def queued_entries(entry, covered)
          previous = previous_covered(entry)

          entries.select do
            it.kind == "queued_message" &&
              it.id.between?(previous + 1, covered) &&
              it.payload.fetch("type") != "report"
          end
        end

        def previous_covered(entry)
          user_entries.filter_map do
            it.payload["covers_through_entry_id"] if it.id < entry.id
          end.max.to_i
        end

        def user_entries = entries.select { it.kind == "user" }

        def visible_texts
          @visible_texts ||= user_entries.filter_map { text(it).presence }
        end
      end
    end
  end
end
