module AimHelmRails
  module Features
    module Workspace
      module Adapters
        class ActiveRecord
          attr_reader :kind, :key, :actor, :tenant

          def initialize(kind:, tenant:, actor: nil, key: "default", model: WorkspaceDocument)
            @kind = kind.to_s.freeze
            @key = key.to_s.freeze
            @actor = actor
            @tenant = tenant
            @model = model
          end

          def read(path)
            model.uncached { relation.where(path: path.to_s).pick(:content) }
          end

          def write(path, content)
            document = relation.find_or_initialize_by(path: path.to_s)
            document.update!(content: content.to_s)
            nil
          end

          def delete(path)
            relation.where(path: path.to_s).delete_all
            nil
          end

          def list(prefix = nil)
            paths = model.uncached { relation.order(:path).pluck(:path) }
            prefix ? paths.select { it.start_with?(prefix.to_s) } : paths
          end

          def atomic_writes? = true

          def snapshot(path)
            content = read(path)
            AimHelm::Features::Workspace::Snapshot.for(content) if content
          end

          def compare_and_write(path, content, expected_revision:)
            expected_revision ? replace(path, content, expected_revision) : create(path, content)
          end

          private

          attr_reader :model

          def relation
            model.unscoped.where(**scope)
          end

          def scope
            { actor_gid: actor&.to_gid&.to_s, tenant_gid: tenant.to_gid.to_s, kind:, key: }
          end

          def create(path, content)
            document = model.create!(**scope, path: path.to_s, content: content.to_s)
            AimHelm::Features::Workspace::Snapshot.for(document.reload.content)
          rescue ::ActiveRecord::RecordNotUnique
            raise unless relation.exists?(path: path.to_s)

            raise conflict(path, expected_revision: nil)
          end

          def replace(path, content, expected_revision)
            model.transaction do
              document = relation.lock.find_by(path: path.to_s)
              actual_revision = revision(document)

              unless actual_revision == expected_revision
                raise conflict(path, expected_revision:, actual_revision:)
              end

              document.update!(content: content.to_s)
              AimHelm::Features::Workspace::Snapshot.for(document.reload.content)
            end
          end

          def revision(document)
            AimHelm::Features::Workspace::Snapshot.for(document.content).revision if document
          end

          def conflict(path, expected_revision:, actual_revision: snapshot(path)&.revision)
            AimHelm::Features::Workspace::ConflictError.new(
              path.to_s,
              expected_revision:,
              actual_revision:,
            )
          end
        end
      end
    end
  end
end
