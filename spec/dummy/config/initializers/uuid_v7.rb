module TestUuidV7PrimaryKey
  def primary_key(name, type = :primary_key, **options)
    options[:default] = options.fetch(:default, "uuidv7()") if type == :uuid

    super
  end
end

ActiveSupport.on_load(:active_record_postgresqladapter) do
  ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.prepend(TestUuidV7PrimaryKey)
end
