class CreateAgentAttachments < ActiveRecord::Migration[8.1]
  def change
    config = Rails.configuration.generators
    primary_key_type = config.options[config.orm][:primary_key_type] || :primary_key
    session_key_type = connection.columns(:agent_sessions).find { it.name == "id" }.type

    create_table :agent_attachments, id: primary_key_type do
      it.string :actor_gid, null: false
      it.string :tenant_gid, null: false
      it.references :session, foreign_key: { to_table: :agent_sessions }, type: session_key_type

      it.timestamps
      it.index %i[tenant_gid actor_gid]
      it.index :created_at, where: "session_id IS NULL"
    end
  end
end
