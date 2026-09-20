module AimHelmRails
  # Tool declarations. Subclasses declare description/schema/needs_approval and
  # implement #call; identity derives from the class path — Charts::Save is identifier
  # "charts/save" and LLM-facing name "charts_save" — so the file is its single source.
  class Tool
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :context

    delegate :session_id, :broadcast, to: :context
    delegate :actor, :tenant, to: :execution

    def execution = context.app

    class << self
      # The config.tools seam: the gem needs only resolve + identifiers (Resolver's interface).
      # Bare AimHelm::Tool constants resolve as themselves, so spec fixtures keep working.
      def resolve(identifier)
        registered = registered_tools[identifier]
        return registered if registered

        constant = "#{name.deconstantize}::Tools::#{identifier.camelize}".constantize
        constant.is_a?(AimHelm::Tool) ? constant : constant.as_aim_helm_tool
      rescue NameError
        raise AimHelm::ConfigurationError, "unknown registered tool #{identifier.inspect}"
      end

      def identifiers(tools)
        tools.map do
          identifier = it.is_a?(String) ? it : it.identifier
          raise ArgumentError, "durable tools require registered identifiers" unless identifier

          resolve(identifier)
          identifier
        end
      end

      def register(*tools)
        tools.each { registered_tools[it.identifier] = it }
      end

      def definition(tool)
        tool.respond_to?(:as_aim_helm_tool) ? tool.as_aim_helm_tool : tool
      end

      def identifier = name.split("::Tools::", 2).last.underscore
      def tool_name = identifier.tr("/", "_")

      def description(value = nil)
        return tool_description unless value

        value = value.freeze
        define_singleton_method(:tool_description) { value }
      end

      # Every schema property becomes an instance attribute, so #call reads arguments as
      # plain readers.
      def schema(&block)
        return tool_schema unless block

        processor = AimHelm::Schema.define(&block)
        processor.json_schema.fetch(:properties).each_key { attribute it }
        define_singleton_method(:tool_schema) { processor }
      end

      # Accepts a callable for argument-dependent gates, per AimHelm's contract.
      # rubocop:disable-next Style/OptionalBooleanParameter -- bare `needs_approval` is the DSL
      def needs_approval(value = true)
        define_singleton_method(:approval_policy) { value }
      end

      def as_aim_helm_tool
        tool_class = self

        @as_aim_helm_tool ||= AimHelm::Tool.define(
          tool_name,
          tool_description,
          identifier:,
          schema: tool_schema,
          needs_approval: approval_policy,
        ) do |arguments, context|
          coerce(tool_class.new(arguments.merge("context" => context)).call)
        end
      end

      # call may return a finished Result or bare content. A hash or array serializes as
      # JSON text: a bare Array as content would read as provider blocks, not data.
      def coerce(result)
        return result if result.is_a?(AimHelm::Tool::Result)

        content = result.is_a?(String) ? result : JSON.generate(result)
        AimHelm::Tool::Result.success(content:)
      end

      def tool_description = ""
      # rubocop:disable-next Naming/PredicateMethod -- a gate value, possibly callable, not a predicate
      def approval_policy = false
      def tool_schema = AimHelm::Tool::EMPTY_SCHEMA

      private

      def registered_tools = @registered_tools ||= {}
    end
  end
end
