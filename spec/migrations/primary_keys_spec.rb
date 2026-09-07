module AimHelmRailsMigrationSpec
  class Database < ActiveRecord::Base
    self.abstract_class = true
  end

  class Actor < Database
    self.table_name = "migration_actors"
  end
end

RSpec.describe "AimHelmRails migration primary keys", type: :model do
  self.use_transactional_tests = false

  let(:database) { AimHelmRailsMigrationSpec::Database }
  let(:connection) { database.connection }
  let(:actor) { AimHelmRailsMigrationSpec::Actor.create!(name: "Actor") }
  let(:tenant) { AimHelmRailsMigrationSpec::Actor.create!(name: "Tenant") }
  let(:session) { AimHelmRails::Session.create!(actor:, tenant:) }
  let(:fixture) { AimHelmRails::Engine.root.join("spec/fixtures/aim_helm_rails/vision.png") }

  let(:models) do
    [AimHelmRails::Session, AimHelmRails::SessionEntry, AimHelmRails::Attachment,
     AimHelmRails::AllowRule, AimHelmRails::WorkspaceDocument,
     ActiveStorage::Blob, ActiveStorage::Attachment, ActiveStorage::VariantRecord,
     AimHelmRailsMigrationSpec::Actor]
  end

  def connect_postgresql
    @schema = "aim_helm_rails_migrations_#{SecureRandom.hex(6)}"
    ActiveRecord::Base.connection.create_schema(@schema)
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    database.establish_connection(config.merge(schema_search_path: @schema))
  end

  def connect_models
    @original_connections = [AimHelmRails::ApplicationRecord, ActiveStorage::Record]
                            .to_h { |model| [model, model.connection_specification_name] }

    @original_connections.each_key do |model|
      model.connection_specification_name = database.name
    end

    # Migrations and real engine/Active Storage models share the isolated database.
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive_messages(
      migration_connection: connection, migration_connection_pool: database.connection_pool,
    )
  end

  def load_engine_models
    # Reload models so their connection and association caches use the isolated database.
    %w[Session SessionEntry Attachment AllowRule WorkspaceDocument].each do |name|
      stub_const("AimHelmRails::#{name}", Class.new(AimHelmRails::ApplicationRecord))
      load AimHelmRails::Engine.root.join("app/models/#{name.underscore}.rb")
    end
  end

  def configure_keys(primary_key_type)
    config = Rails.configuration.generators
    options = config.options.deep_dup
    options[config.orm][:primary_key_type] = primary_key_type
    allow(config).to receive(:options).and_return(options)
  end

  def migrate_with_keys(primary_key_type)
    paths = [ActiveStorage::Engine.root.join("db/migrate").to_s,
             AimHelmRails::Engine.root.join("db/migrate").to_s]

    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::MigrationContext.new(paths).migrate
    end

    connection.create_table(:migration_actors, id: primary_key_type || :primary_key) do |table|
      table.string :name
    end

    models.each(&:reset_column_information)
  end

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  after do
    AimHelmRails::Attachment.find_each { |attachment| attachment.file.purge }

    @original_connections.each do |model, name|
      model.connection_specification_name = name
    end

    models.each(&:reset_column_information)
    database.remove_connection
    ActiveRecord::Base.connection.drop_schema(@schema) if @schema
  end

  [["postgresql", :uuid], ["postgresql", nil], ["sqlite3", nil]].each do |adapter, key_type|
    context "with #{adapter} and #{key_type || "default"} host keys" do
      before do
        if adapter == "sqlite3"
          database.establish_connection(adapter:, database: ":memory:")
        else
          connect_postgresql
        end

        connect_models
        load_engine_models
        configure_keys(key_type)
        migrate_with_keys(key_type)
      end

      it "keeps sessions UUIDv7 and entries integer regardless of the host key type" do
        child = AimHelmRails::Session.create!(actor:, tenant:, parent_session: session)
        entry = child.entries
                     .create!(kind: "user", payload: { content: "Hello" }, created_at: Time.current)

        expect(session.id)
          .to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
        expect(child.reload.parent_session).to eq(session)
        expect(entry.reload.session).to eq(child)
        expect(entry.id).to be_a(Integer)
      end

      it "stages, joins, downloads, and claims a file using the host's Active Storage keys" do
        attachment = File.open(fixture) do |io|
          AimHelmRails::Attachment.create!(
            actor:, tenant:, file: { io:, filename: "vision.png", content_type: "image/png" },
          )
        end

        expect(AimHelmRails::Session.count).to eq(0)
        expect(attachment.id).to be_a(key_type == :uuid ? String : Integer)
        expect(attachment.file_attachment.reload.record_id).to eq(attachment.id)
        expect(attachment.file_attachment.record).to eq(attachment)
        joined = AimHelmRails::Attachment.joins(:file_attachment).find(attachment.id)
        expect(joined).to eq(attachment)
        expect(attachment.reload.file.download).to eq(File.binread(fixture))
        expect(attachment.thumbnail(32).processed.download).not_to be_empty

        AimHelmRails::Attachment.claim!([attachment.to_gid_param], session:, actor:, tenant:)

        expect(attachment.reload.session).to eq(session)
        expect(attachment.actor).to eq(actor)
        expect(attachment.tenant).to eq(tenant)
        expect(attachment.id[14]).to eq("7") if key_type == :uuid

        expect { attachment.update_columns(session_id: SecureRandom.uuid_v7) }
          .to raise_error(ActiveRecord::InvalidForeignKey)
      end

      it "uses the host's keys for allow rules and workspace documents" do
        rule = AimHelmRails::AllowRule.create!(actor:, tenant:, tool_name: "read")
        document = AimHelmRails::WorkspaceDocument.create!(
          actor:, tenant:, kind: "memory", path: "notes.md", content: "Remember this",
        )

        [rule, document].each do |record|
          expect(record.reload.id).to be_a(key_type == :uuid ? String : Integer)
          expect(record.actor).to eq(actor)
          expect(record.tenant).to eq(tenant)
          expect(record.id[14]).to eq("7") if key_type == :uuid
        end
      end

      it "enforces session foreign keys" do
        expect { session.update_columns(parent_session_id: SecureRandom.uuid_v7) }
          .to raise_error(ActiveRecord::InvalidForeignKey)

        expect do
          AimHelmRails::SessionEntry
            .insert_all!([{ session_id: SecureRandom.uuid_v7, kind: "user", payload: {},
                            created_at: Time.current }])
        end.to raise_error(ActiveRecord::InvalidForeignKey)
      end
    end
  end
end
