module AimHelmRails
  class Session
    class History
      def initialize(entries, child_sessions:)
        @entries = entries.sort_by(&:id)
        @child_sessions = child_sessions.index_by { it.id.to_s }
        @user_messages = UserMessages.new(@entries)
      end

      def title = user_messages.title

      # The working context is the newest aside pin anywhere in the chat's tree.
      def aside_pin
        pins = entries.select { aside_pin?(it) } + child_sessions.values.filter_map(&:aside_pin)
        pins.max_by(&:id)
      end

      def message_count = entries.count { it.kind == "assistant" } + user_messages.count

      def runs
        entries.group_by(&:run_id).filter_map do |run_id, run_entries|
          run_payload(run_id, run_entries) if run_id
        end
      end

      private

      attr_reader :child_sessions, :entries, :user_messages

      def run_payload(run_id, run_entries)
        user = run_entries.find { it.kind == "user" }
        items = run_entries.flat_map { history_items(it, run_entries) }
        return if user.nil? && items.empty?

        payload(run_id, user, items, run_entries)
      end

      def payload(run_id, user, items, run_entries)
        terminal = run_entries.find { it.kind == "terminal" }
        message = user_messages.text(user)
        {
          run_id:,
          attachments: user_messages.attachments(user),
          message: message.presence,
          items:,
          user_timestamp: message.present? ? user.created_at.iso8601 : nil,
          assistant_timestamp: terminal&.created_at&.iso8601,
        }
      end

      def content_items(entry)
        entry.payload.fetch("content").each_with_index.filter_map do |block, index|
          case block.fetch("type")
          when "text"
            { type: "text", content: block.fetch("text"), index:, turn_id: entry.turn_id }
          when "thinking"
            { type: "thinking", content: block.fetch("thinking"), index:, turn_id: entry.turn_id }
          end
        end
      end

      def history_items(entry, run_entries)
        case entry.kind
        when "assistant" then content_items(entry) + usage_items(entry)
        when "usage" then usage_items(entry)
        when "subagent" then [subagent_item(entry)]
        when "tool_result" then tool_items(entry)
        when "tool_started" then [tool_status(entry, run_entries)]
        else []
        end
      end

      def usage_items(entry) = [AimHelm::Session::Usage::Step.history_item(entry)].compact

      def subagent_item(entry)
        session_id = entry.payload.fetch("id")

        {
          type: "subagent",
          call_id: entry.payload.fetch("call_id"),
          name: entry.payload.fetch("name"),
          runs: child_sessions.fetch(session_id).history_runs,
          session_id:,
          task: entry.payload.fetch("task"),
          turn_id: entry.turn_id,
        }
      end

      def tool_status(entry, run_entries)
        call_id = entry.payload.fetch("call_id")
        call = tool_entry(run_entries, "tool_call", "id", call_id)
        result = tool_entry(run_entries, "tool_result", "call_id", call_id)
        status = result_status(result)
        { type: "tool", call_id:, name: call.payload.fetch("name"),
          arguments: call.payload["arguments"], preview: preview_image(result),
          status:, error: status == "failed" ? error_text(result) : nil,
          turn_id: entry.turn_id }
      end

      def error_text(result)
        output = result.payload.fetch("output")
        return output.to_s unless output.is_a?(Array)

        output.filter_map { it["text"] if it["type"] == "text" }.join(" ")
      end

      # An image block in the result output resurfaces as the data URI `tool.preview` showed live.
      def preview_image(result)
        return unless result

        output = result.payload.fetch("output")
        return unless output.is_a?(Array)

        source = output.filter_map { it["source"] if it["type"] == "image" }.first
        "data:#{source["media_type"]};base64,#{source["data"]}" if source
      end

      def tool_entry(entries, kind, key, call_id)
        entries.find do
          it.kind == kind && it.payload.fetch(key) == call_id
        end
      end

      def result_status(result)
        return "started" unless result

        result.payload.fetch("error") ? "failed" : "done"
      end

      def aside_pin?(entry)
        entry.kind == "tool_result" && entry.payload.dig("metadata", "resource",
                                                         "placement") == "aside"
      end

      # Only inline renders become transcript blocks; aside pins live in the context pane.
      def tool_items(entry)
        resource = entry.payload.dig("metadata", "resource")
        return [] if resource.nil? || aside_pin?(entry)

        [Resource.presentation(resource, key: entry.payload.fetch("call_id"))
                 .merge(type: "resource", turn_id: entry.turn_id)]
      end
    end
  end
end
