module AimHelmRails
  # What a chat runs on, spelled out by its key: "analyst" is that helmsman as declared,
  # "analyst:gpt-5.6-terra/low" overrides its model and reasoning. The label is what the person
  # reads; a key nobody labelled reads as itself.
  class ChatOptions
    KEY = %r{\A(?<helmsman>[^:]+)(?::(?<model>[^/]+)/(?<reasoning>[^/]+))?\z}

    attr_reader :key, :label, :helmsman, :model, :reasoning

    class << self
      def all = AimHelmRails.host.chat_options.map { new(**it) }

      # The composer's choices: a chat opened on a key is pinned to it, any other unsaved chat
      # picks from the host's list.
      def for(chat)
        key = chat.helmsman
        key ? [all.find { it.key == key } || new(key:)] : all
      end

      # Selected to begin with: the choice that runs a helmsman as declared, else the first.
      def chosen(options) = options.find(&:declared?) || options.first
    end

    def declared?
      declared = AimHelmRails.host.helmsman(helmsman)
      [model, reasoning] == [declared.helmsman_model, declared.helmsman_reasoning]
    end

    def initialize(key:, label: key)
      parts = KEY.match(key) ||
              raise(AimHelm::ConfigurationError,
                    "chat options #{key.inspect} are not helmsman:model/reasoning")
      @key = key
      @label = label
      @helmsman = parts[:helmsman]
      @model = parts[:model]
      @reasoning = parts[:reasoning]&.to_sym
      AimHelm.models.fetch(model) if model
    end

    def agent
      declared = AimHelmRails.host.helmsman(helmsman).agent
      model ? declared.with(model:, reasoning:) : declared
    end

    def as_json(*) = { key:, label: }
  end
end
