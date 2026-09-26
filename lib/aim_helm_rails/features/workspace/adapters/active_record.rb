module AimHelmRails
  module Features
    class Workspace
      module Adapters
        class ActiveRecord
          attr_reader :kind, :key, :actor, :tenant, :root

          # `root` scopes the store to a folder: paths go in and come out relative to it.
          def initialize(kind:, tenant:, actor: nil, key: "default", root: "")
            @kind = kind.to_s.freeze
            @key = key.to_s.freeze
            @actor = actor
            @tenant = tenant
            @root = root.to_s.freeze
            @readonly = false
          end

          # The same store, refusing every write with ReadOnly.
          def readonly = dup.tap { it.readonly = true }
          def readonly? = @readonly

          def read(path)
            model.uncached { documents.where(path: path!(path)).pick(:content) }
          end

          def write(path, content)
            writable!
            document = documents.find_or_initialize_by(path: path!(path))
            document.update!(content: content.to_s)
            nil
          end

          def delete(path)
            writable!
            documents.where(path: path!(path)).delete_all
            nil
          end

          def list(prefix = nil, text: nil)
            model.uncached { listing(prefix, text).pluck(:path) }.map { it.delete_prefix(root) }
          end

          # { path => content } for every document.
          def read_all
            rows = model.uncached { documents.pluck(:path, :content) }
            rows.to_h { |path, content| [path.delete_prefix(root), content] }
          end

          # [path, bytes, lines, updated_at]; a line is a newline, so a file without a trailing
          # one is short by one. octet_length needs SQLite 3.43 or later.
          def entries(prefix = nil, text: nil)
            newline_count = ["length(content) - length(replace(content, ?, ''))", "\n"]
            lines = Arel.sql(model.sanitize_sql_array(newline_count))
            bytes = Arel.sql("octet_length(content)")
            rows = model.uncached { listing(prefix, text).pluck(:path, bytes, lines, :updated_at) }
            rows.map { |path, *rest| [path.delete_prefix(root), *rest] }
          end

          def atomic_writes? = true

          def snapshot(path)
            content = read(path)
            AimHelmRails::Features::Workspace::Snapshot.for(content) if content
          end

          def compare_and_write(path, content, expected_revision:)
            writable!
            expected_revision ? replace(path, content, expected_revision) : create(path, content)
          end

          def documents
            scope = model.unscoped.where(**self.scope)
            root.empty? ? scope : under(scope, root)
          end

          protected

          attr_writer :readonly

          private

          def model = AimHelmRails::WorkspaceDocument
          def writable! = readonly? && raise(ReadOnly, "#{kind} is read-only here")

          # The stored path carries the root, so the length limit applies to the whole.
          def path!(path) = Workspace.path!("#{root}#{Workspace.path!(path)}")

          def listing(prefix, text)
            scope = documents.order(:path)
            scope = under(scope, "#{root}#{prefix}") if prefix
            text ? scope.merge(mentioning(text)) : scope
          end

          def under(scope, folder)
            scope.where("path LIKE ?", "#{model.sanitize_sql_like(folder)}%")
          end

          def mentioning(text)
            term = "%#{model.sanitize_sql_like(text)}%"
            table = model.arel_table
            model.where(table[:path].matches(term).or(table[:content].matches(term)))
          end

          def scope
            { actor_gid: actor&.to_gid&.to_s, tenant_gid: tenant.to_gid.to_s, kind:, key: }
          end

          def create(path, content)
            document = model.create!(**scope, path: path!(path), content: content.to_s)
            AimHelmRails::Features::Workspace::Snapshot.for(document.reload.content)
          rescue ::ActiveRecord::RecordNotUnique
            raise unless documents.exists?(path: path!(path))

            raise conflict(path, expected_revision: nil)
          end

          def replace(path, content, expected_revision)
            model.transaction do
              document = documents.lock.find_by(path: path!(path))
              actual_revision = revision(document)

              unless actual_revision == expected_revision
                raise conflict(path, expected_revision:, actual_revision:)
              end

              document.update!(content: content.to_s)
              AimHelmRails::Features::Workspace::Snapshot.for(document.reload.content)
            end
          end

          def revision(document)
            AimHelmRails::Features::Workspace::Snapshot.for(document.content).revision if document
          end

          def conflict(path, expected_revision:, actual_revision: snapshot(path)&.revision)
            AimHelmRails::Features::Workspace::ConflictError.new(
              path!(path),
              expected_revision:,
              actual_revision:,
            )
          end
        end
      end
    end
  end
end
