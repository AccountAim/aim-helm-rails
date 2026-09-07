module AimHelmRailsSpec
  module Host
    module_function

    def tools = AimHelmRails::Tool
    def helmsman(name) = raise(KeyError, name)
    def resource_path(gid, frame:) = "/host/resources/#{gid}?frame=#{frame}"

    def authorize!(record, actor:, tenant:, action:)
      raise ArgumentError, action unless %i[read update].include?(action)

      raise ActiveRecord::RecordNotFound unless record.actor == actor && record.tenant == tenant
    end
  end
end

RSpec.configure do |config|
  config.before do |example|
    path = File.expand_path(example.metadata.fetch(:file_path))
    next unless path.start_with?(AimHelmRails::Engine.root.join("spec/").to_s)

    allow(AimHelmRails).to receive(:host).and_return(AimHelmRailsSpec::Host)
    @previous_aim_helm_tools = AimHelm.config.tools
    AimHelm.configure { it.tools = AimHelmRails::Tool }
    AimHelmRails::Features::Workspace.register(AimHelmRails::Tool)
  end

  config.after do
    AimHelm.configure { it.tools = @previous_aim_helm_tools } if @previous_aim_helm_tools
  end
end
