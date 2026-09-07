class CreateAgentSessionsAndEntries < ActiveRecord::Migration[8.1]
  def change
    session_key_type = connection.native_database_types.key?(:uuid) ? :uuid : :string

    create_table :agent_sessions, id: session_key_type do
      it.string :actor_gid, null: false
      it.string :tenant_gid, null: false
      it.string :execution_actor_gid
      it.column :parent_session_id, session_key_type, index: true
      it.string :name
      # The helmsman an interactive session runs; subagent sessions carry theirs in the log.
      it.string :helmsman
      # A person watches an interactive session; headless ones answer a caller and are not listed.
      it.boolean :interactive, null: false, default: false
      it.string :status, null: false, default: "queued", index: true
      it.string :claimed_by
      it.string :lease_token
      it.datetime :heartbeat_at
      it.timestamps

      it.index %i[tenant_gid actor_gid updated_at], where: "interactive"
    end

    create_table :agent_session_entries, id: :bigint do
      it.column :session_id, session_key_type, null: false
      it.string :kind, null: false
      it.json :payload, null: false
      it.string :key
      it.string :run_id
      it.string :turn_id
      it.datetime :created_at, null: false
    end

    add_index :agent_session_entries, %i[session_id id]
    add_foreign_key :agent_session_entries, :agent_sessions, column: :session_id
    add_foreign_key :agent_sessions, :agent_sessions, column: :parent_session_id
    add_index :agent_session_entries, %i[session_id key], unique: true,
                                                          where: "key IS NOT NULL"
  end
end
