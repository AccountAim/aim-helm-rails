module AimHelmRails
  # Text budgets for a list row, a full resource read, and CLI exploration.
  class ClippedJson
    BUDGETS = { brief: 500, full: 100_000, raw: nil }.freeze

    class << self
      def call(text, detail:, hint: nil)
        limit = BUDGETS.fetch(detail)
        return text if text.nil? || limit.nil? || text.bytesize <= limit

        "#{text.truncate_bytes(limit, omission: "")}\n" \
          "… [truncated: showing #{limit} of #{text.bytesize} bytes#{"; #{hint}" if hint}]"
      end
    end
  end
end
