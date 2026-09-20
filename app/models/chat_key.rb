module AimHelmRails
  # What a chat runs on: "analyst" is that helmsman as declared, "analyst:gpt-5.6-terra/low"
  # overrides its model and reasoning.
  class ChatKey
    FORMAT = %r{\A(?<helmsman>[^:]+)(?::(?<model>[^/]+)/(?<reasoning>[^/]+))?\z}

    attr_reader :helmsman, :model, :reasoning

    def initialize(key)
      parts = FORMAT.match(key) || raise(ArgumentError, "not helmsman[:model/reasoning]: #{key}")
      @key = key
      @helmsman = parts[:helmsman]
      @model = parts[:model]
      @reasoning = parts[:reasoning]&.to_sym
    end

    def to_s = @key

    def agent
      declared = AimHelmRails.host.helmsman(helmsman).agent
      model ? declared.with(model:, reasoning:) : declared
    end
  end
end
