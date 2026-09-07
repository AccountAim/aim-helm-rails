# frozen_string_literal: true

module AimHelm
  module Features
    class Workspace
      class Edit
        Result = Data.define(:content, :count)
        MAX_ATTEMPTS = 3

        def self.call(adapter, path:, old_string:, new_string:, replace_all: false)
          new(adapter, path:, old_string:, new_string:, replace_all:).call
        end

        def initialize(adapter, path:, old_string:, new_string:, replace_all:)
          @adapter = adapter
          @path = path
          @old_string = old_string
          @new_string = new_string
          @replace_all = replace_all
        end

        def call
          atomic? ? atomically : legacy
        end

        private

        attr_reader :adapter, :path, :old_string, :new_string, :replace_all

        def atomically
          MAX_ATTEMPTS.times do
            snapshot = adapter.snapshot(path)
            raise EditError, "document does not exist" unless snapshot

            result = replacement(snapshot.content)

            begin
              return commit(result, snapshot.revision)
            rescue ConflictError
              raise if it == MAX_ATTEMPTS - 1
            end
          end
        end

        def legacy
          content = adapter.read(path)
          raise EditError, "document does not exist" unless content

          replacement(content).tap { adapter.write(path, it.content) }
        end

        def commit(result, revision)
          committed = adapter.compare_and_write(path, result.content, expected_revision: revision)

          unless committed.content.b == result.content.b
            raise EditError, "write committed with different content; read the document again"
          end

          result
        end

        def replacement(content)
          count = match_count(content)
          replaced = replace(content)
          raise EditError, "the edit changed nothing" if replaced == content

          Result.new(content: replaced, count: replace_all ? count : 1)
        end

        def match_count(content)
          count = content.scan(old_string).length
          raise EditError, "old_string was not found" if count.zero?
          raise EditError, ambiguous(count) if count > 1 && !replace_all

          count
        end

        def replace(content)
          return content.gsub(old_string) { new_string } if replace_all

          content.sub(old_string) { new_string }
        end

        def ambiguous(count)
          "old_string matched #{count} places; include more context or set replace_all"
        end

        def atomic?
          adapter.respond_to?(:atomic_writes?) && adapter.atomic_writes?
        end
      end
    end
  end
end
