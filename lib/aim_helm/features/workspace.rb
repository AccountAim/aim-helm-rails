# frozen_string_literal: true

require "digest"

module AimHelm
  module Features
    class Workspace
      Snapshot = Data.define(:content, :revision) do
        def initialize(content:, revision:)
          super(content: content.dup.freeze, revision: revision.dup.freeze)
        end

        def self.for(content)
          new(content:, revision: Digest::SHA256.hexdigest(content.b))
        end
      end

      class ConflictError < StandardError
        attr_reader :path, :expected_revision, :actual_revision

        def initialize(path, expected_revision: nil, actual_revision: nil)
          @path = path
          @expected_revision = expected_revision
          @actual_revision = actual_revision

          super("#{path.inspect} changed; read it again")
        end
      end

      class EditError < StandardError; end

      attr_reader :adapter

      def self.adapter(adapter = nil, &resolver)
        raise ArgumentError, "pass an adapter or a resolver block" if adapter.nil? == resolver.nil?

        new(adapter:, resolver:)
      end

      def initialize(adapter:, resolver:)
        @adapter = adapter
        @resolver = resolver
      end

      def tools(name:, purpose:, only: Tools::OPERATIONS)
        Tools.new(self, name:, purpose:, only:).to_a
      end

      def adapter_for(context = nil) = @resolver ? @resolver.call(context) : adapter
      def read(...) = adapter_for.read(...)
      def write(...) = adapter_for.write(...)
      def delete(...) = adapter_for.delete(...)
      def list(...) = adapter_for.list(...)
      def atomic_writes? = adapter_for.atomic_writes?
      def snapshot(...) = adapter_for.snapshot(...)
      def compare_and_write(...) = adapter_for.compare_and_write(...)
    end
  end
end
