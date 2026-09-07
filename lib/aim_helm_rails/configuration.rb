module AimHelmRails
  mattr_accessor :host_class
  mattr_accessor :controller_class, default: "::ApplicationController"

  def self.host
    unless host_class
      raise AimHelm::ConfigurationError,
            "Set AimHelmRails.host_class to the host integration class"
    end

    host_class.constantize
  end

  # Shared table names are independent of the engine's isolated Ruby namespace.
  def self.table_name_prefix = "agent_"
end
