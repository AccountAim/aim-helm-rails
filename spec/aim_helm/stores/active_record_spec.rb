# frozen_string_literal: true

require File.join(
  Gem.loaded_specs.fetch("aim-helm").full_gem_path,
  "spec/support/store_contract",
)

module AimHelmActiveRecordStoreSpec
  class SQLiteBase < ::ActiveRecord::Base
    self.abstract_class = true
  end

  class SQLiteSession < SQLiteBase
    self.table_name = "agent_sessions"

    has_many :entries,
             class_name: "AimHelmActiveRecordStoreSpec::SQLiteEntry",
             foreign_key: :session_id
  end

  class SQLiteEntry < SQLiteBase
    self.table_name = "agent_session_entries"

    belongs_to :session,
               class_name: "AimHelmActiveRecordStoreSpec::SQLiteSession",
               foreign_key: :session_id
  end
end

RSpec.describe AimHelm::Stores::ActiveRecord, type: :model do
  sqlite_skip = "sqlite3 is not in the host bundle" unless Gem.loaded_specs.key?("sqlite3")

  context "with PostgreSQL" do
    let(:user) do
      User.create!(organization: test_organization, name: "Store User",
                   email: "store-#{SecureRandom.uuid_v7}@example.com")
    end

    let(:prepare_session) do
      ->(id) { AimHelmRails::Session.create!(id:, actor: user, tenant: user.organization) }
    end

    let(:store) { AimHelm.config.store }

    it_behaves_like "a AimHelm store"

    it "updates the status cache in the append transaction" do
      session = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
      run_id = SecureRandom.uuid_v7

      store.append(session.id, :user, { content: [] }, run_id:)
      expect(session.reload.status).to eq("queued")

      store.append(session.id, :assistant, { content: [] }, run_id:)
      expect(session.reload.status).to eq("running")

      store.append(session.id, :approval_request, { call_id: "call-1" }, run_id:)
      expect(session.reload.status).to eq("awaiting_approval")

      store.append(session.id, :approval_request, { call_id: "call-2" }, run_id:)
      store.append(session.id, :approval_decision, { call_id: "call-1" }, run_id:)
      store.append(session.id, :tool_result, { call_id: "free-call" }, run_id:)
      expect(session.reload.status).to eq("awaiting_approval")

      store.append(session.id, :approval_decision, { call_id: "call-2" }, run_id:)
      expect(session.reload.status).to eq("queued")

      store.append(
        session.id,
        :terminal,
        { outcome: "done" },
        key: "terminal",
        run_id:,
      )
      expect(session.reload.status).to eq("completed")

      store.append(session.id, :usage, { purpose: :compaction }, run_id:)
      store.append(
        session.id,
        :compaction,
        { summary: "Earlier work", covers_through_entry_id: 1 },
        run_id:,
      )
      expect(session.reload.status).to eq("completed")
    end
  end

  context "with SQLite", skip: sqlite_skip do
    before do
      AimHelmActiveRecordStoreSpec::SQLiteBase.establish_connection(
        adapter: "sqlite3",
        database: ":memory:",
      )
      connection = AimHelmActiveRecordStoreSpec::SQLiteBase.connection

      connection.create_table(:agent_sessions, id: :string) do |table|
        table.string :user_id, null: false
        table.string :status, null: false, default: "queued"
        table.timestamps
      end

      connection.create_table(:agent_session_entries) do |table|
        table.string :session_id, null: false
        table.string :kind, null: false
        table.json :payload, null: false
        table.string :key
        table.string :run_id
        table.string :turn_id
        table.datetime :created_at, null: false
      end

      connection.add_index(
        :agent_session_entries,
        %i[session_id key],
        unique: true,
        where: "key IS NOT NULL",
        name: AimHelm::Stores::ActiveRecord::KEY_INDEX,
      )
      AimHelmActiveRecordStoreSpec::SQLiteSession.reset_column_information
      AimHelmActiveRecordStoreSpec::SQLiteEntry.reset_column_information
    end

    after { AimHelmActiveRecordStoreSpec::SQLiteBase.connection_pool.disconnect! }

    let(:prepare_session) do
      ->(id) { AimHelmActiveRecordStoreSpec::SQLiteSession.create!(id:, user_id: SecureRandom.uuid_v7) }
    end

    let(:store) do
      described_class.new(
        session_model: AimHelmActiveRecordStoreSpec::SQLiteSession,
        key_index: AimHelm::Stores::ActiveRecord::KEY_INDEX,
      )
    end

    it_behaves_like "a AimHelm store"
  end
end
