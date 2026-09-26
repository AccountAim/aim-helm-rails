module AimHelmRails
  module Features
    class Workspace
      # One shell over the documents a call names, scratch the only writable mount.
      # `resolver.call(mount, context)` supplies each store's adapter.
      module Bash
        MOUNTS = %w[scratch memory knowledge_base].freeze

        SCHEMA = AimHelm::Schema.define do
          required(:script).filled(:string)
          optional(:paths)
            .array(:string)
            .documentation(description: <<~TEXT.squish)
              Files the script reads, as a list tool or a clipped read prints them, e.g.
              knowledge_base/ops/routes.md or scratch/clips/x/query.sql; each appears at
              /<that path>.
            TEXT
        end

        module_function

        def define(&)
          AimHelm::Tool.define(
            "workspace_bash",
            "Run a bash script over workspace files. #{Shell::GUIDE}",
            identifier: "workspace/bash",
            schema: SCHEMA,
          ) { |arguments, context| call(arguments, context, &) }
        end

        def call(arguments, context)
          stores = MOUNTS.to_h { [it, yield(it, context)] }
          paths = arguments.fetch("paths", [])
          report = Shell.call(stores, arguments.fetch("script"), paths:)
          AimHelm::Tool::Result.success(content: JSON.generate(report.to_h))
        rescue InvalidPath => e
          AimHelm::Tool::Result.failure(content: "workspace_bash: #{e.message}")
        end
      end
    end
  end
end
