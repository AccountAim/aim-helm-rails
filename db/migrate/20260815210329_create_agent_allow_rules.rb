class CreateAgentAllowRules < ActiveRecord::Migration[8.1]
  def change
    config = Rails.configuration.generators
    primary_key_type = config.options[config.orm][:primary_key_type] || :primary_key

    create_table :agent_allow_rules, id: primary_key_type do
      it.string :actor_gid, null: false
      it.string :tenant_gid, null: false
      it.string :tool_name, null: false

      it.timestamps
    end

    add_index :agent_allow_rules, %i[tenant_gid actor_gid tool_name], unique: true
  end
end
