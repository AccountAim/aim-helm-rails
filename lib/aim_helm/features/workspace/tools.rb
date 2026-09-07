# frozen_string_literal: true

module AimHelm
  module Features
    class Workspace
      class Tools
        OPERATIONS = %i[list read write edit search].freeze

        SCHEMAS = {
          list: AimHelm::Schema.define do
            optional(:prefix).maybe(:string)
          end,
          read: AimHelm::Schema.define do
            required(:path).filled(:string)
            optional(:offset).filled(:integer)
            optional(:limit).filled(:integer)
          end,
          write: AimHelm::Schema.define do
            required(:path).filled(:string)
            required(:content).value(:string)
          end,
          edit: AimHelm::Schema.define do
            required(:path).filled(:string)
            required(:old_string).filled(:string)
            required(:new_string).value(:string)
            optional(:replace_all).filled(:bool)
          end,
          search: AimHelm::Schema.define do
            required(:query).filled(:string)
            optional(:path).filled(:string)
            optional(:prefix).filled(:string)
            optional(:before).filled(:integer)
            optional(:after).filled(:integer)
            optional(:max_matches).filled(:integer)
          end,
        }.freeze

        private_constant :SCHEMAS

        def initialize(workspace, name:, purpose:, only:)
          @workspace = workspace
          @name = name.to_s
          @purpose = purpose.to_s
          @only = only.map(&:to_sym)

          unknown = @only - OPERATIONS
          raise ArgumentError, "unknown workspace operations: #{unknown.join(", ")}" if unknown.any?
        end

        def to_a = @only.map { tool(it) }

        private

        attr_reader :workspace, :name, :purpose

        def tool(operation)
          AimHelm::Tool.define(
            "#{name}_#{operation}",
            description(operation),
            identifier: "workspace/#{name}/#{operation}",
            schema: SCHEMAS.fetch(operation),
          ) do |arguments, context|
            send(operation, workspace.adapter_for(context), arguments)
          end
        end

        def description(operation)
          action = {
            list: "List document paths",
            read: "Read a line-numbered document",
            write: "Create or fully overwrite a document",
            edit: "Replace an exact snippet copied without displayed path or line prefixes",
            search: "Literal grep with before/after context; output markers are display-only",
          }.fetch(operation)

          "#{action} in #{purpose}"
        end

        def list(adapter, arguments)
          paths = adapter.list(arguments["prefix"])
          content = paths.empty? ? "No documents found." : paths.join("\n")
          AimHelm::Tool::Result.success(content:)
        end

        def read(adapter, arguments)
          content = adapter.read(arguments.fetch("path"))
          return missing(arguments.fetch("path")) unless content

          AimHelm::Tool::Result.success(
            content: Window.call(content, offset: arguments["offset"], limit: arguments["limit"]),
          )
        end

        def write(adapter, arguments)
          path = arguments.fetch("path")
          content = arguments.fetch("content")
          adapter.write(path, content)

          AimHelm::Tool::Result.success(content: "Wrote #{path} (#{content.length} chars)")
        end

        def edit(adapter, arguments)
          result = perform_edit(adapter, arguments)

          AimHelm::Tool::Result.success(
            content: "Replaced #{result.count} occurrence(s) in #{arguments.fetch("path")}",
          )
        rescue EditError => e
          AimHelm::Tool::Result.failure(content: "#{name}_edit failed: #{e.message}")
        rescue ConflictError
          AimHelm::Tool::Result.failure(
            content: "#{arguments.fetch("path").inspect} kept changing; read it again",
          )
        end

        def search(adapter, arguments)
          content = Search.call(
            adapter,
            arguments.fetch("query"),
            search_options(arguments),
          )
          AimHelm::Tool::Result.success(content:)
        rescue ArgumentError => e
          AimHelm::Tool::Result.failure(content: "#{name}_search failed: #{e.message}")
        rescue Search::MissingDocument => e
          missing(e.message)
        end

        def perform_edit(adapter, arguments)
          Edit.call(
            adapter,
            path: arguments.fetch("path"),
            old_string: arguments.fetch("old_string"),
            new_string: arguments.fetch("new_string"),
            replace_all: arguments["replace_all"] == true,
          )
        end

        def search_options(arguments)
          arguments.slice(*%w[path prefix before after max_matches]).transform_keys(&:to_sym)
        end

        def missing(path)
          AimHelm::Tool::Result.failure(
            content: "No document at #{path.inspect}. Use #{name}_list to see paths.",
          )
        end
      end
    end
  end
end
