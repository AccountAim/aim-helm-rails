class CreateAgentWorkspaceDocuments < ActiveRecord::Migration[8.1]
  def change
    config = Rails.configuration.generators
    primary_key_type = config.options[config.orm][:primary_key_type] || :primary_key

    create_table :agent_workspace_documents, id: primary_key_type do
      it.string :actor_gid
      it.string :tenant_gid, null: false
      it.string :kind, null: false
      it.string :key, null: false, default: "default"
      it.string :path, null: false, limit: 512
      it.text :content, null: false
      it.timestamps

      it.index %i[tenant_gid kind key path],
               unique: true,
               where: "actor_gid IS NULL",
               name: "index_agent_workspace_documents_shared"
      it.index %i[tenant_gid actor_gid kind key path],
               unique: true,
               where: "actor_gid IS NOT NULL",
               name: "index_agent_workspace_documents_owned"
    end
  end
end
