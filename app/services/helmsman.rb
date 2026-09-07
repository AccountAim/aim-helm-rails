module AimHelmRails
  # Helmsman declarations. Subclasses declare model/instructions/tools and
  # identity derives from the class name — Researcher is the agent named "researcher" — so
  # the file is its single source. agent assembles the AimHelm agent.
  class Helmsman
    COMPACTION_MODEL = ENV.fetch("COMPACTION_MODEL", "gpt-5.6-luna").freeze
    COMPACT_AFTER_TOKENS = ENV.fetch("COMPACT_AFTER_TOKENS", 250_000).to_i

    class << self
      def agent
        AimHelm.agent(
          helmsman_model,
          advance: helmsman_advance_mode,
          compaction:,
          description: helmsman_description, instructions: helmsman_instructions,
          max_turns: helmsman_max_turns,
          name: helmsman_name, reasoning: helmsman_reasoning,
          subagents: subagents.presence,
          tools: helmsman_tools.map { AimHelmRails::Tool.definition(it) }
        )
      end

      # :inline runs the helmsman in the caller's process; the default queues it on the worker.
      def advance(mode)
        define_singleton_method(:helmsman_advance_mode) { mode }
      end

      def model(value = nil)
        return helmsman_model unless value

        value = value.freeze
        define_singleton_method(:helmsman_model) { value }
      end

      def description(value = nil)
        return helmsman_description unless value

        value = value.freeze
        define_singleton_method(:helmsman_description) { value }
      end

      def reasoning(value = nil)
        return helmsman_reasoning unless value

        define_singleton_method(:helmsman_reasoning) { value }
      end

      def max_turns(value = nil)
        return helmsman_max_turns unless value

        define_singleton_method(:helmsman_max_turns) { value }
      end

      def tools(classes = nil)
        return helmsman_tools unless classes

        classes.freeze
        define_singleton_method(:helmsman_tools) { classes }
      end

      # A grant names one mode; whether a specialist runs inline or in background is the
      # helmsman author's call, not the model's.
      def subagent(helmsman, mode:)
        entries = [*subagent_entries, [helmsman, mode]].freeze
        define_singleton_method(:subagent_entries) { entries }
      end

      # Instructions are the prose after __END__ in the helmsman's own file — plain text, no
      # heredoc scaffolding. Read on every build, so a prompt edit lands without a reload.
      def helmsman_instructions
        _, text = File.read(Object.const_source_location(name).first).split(/^__END__\n/, 2)
        text.to_s.strip
      end

      def helmsman_name = name.demodulize.underscore
      def helmsman_advance_mode = nil
      def helmsman_description = nil
      def helmsman_max_turns = 20
      def helmsman_reasoning = nil
      def helmsman_tools = [].freeze
      def subagent_entries = [].freeze

      private

      def subagents
        subagent_entries.map do |helmsman, mode|
          AimHelm::Subagent.new(agent: helmsman.agent, modes: [mode])
        end
      end

      def compaction
        context = AimHelm.models.fetch(helmsman_model).context
        AimHelm::Compaction.new(
          model: COMPACTION_MODEL,
          threshold: COMPACT_AFTER_TOKENS.fdiv(context),
        )
      end
    end
  end
end
