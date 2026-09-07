RSpec.describe AimHelmRails::Tool do
  it "exposes the durable execution identities to host tools" do
    actor = Organization.create!(name: "Service actor")
    tenant = test_organization
    execution = AimHelmRails::ExecutionContext.new(actor:, tenant:)
    tool = described_class.new(context: double(app: execution))

    expect(tool.execution).to eq(execution)
    expect(tool.actor).to eq(actor)
    expect(tool.tenant).to eq(tenant)
  end

  it "resolves tools from the host's namespace" do
    stub_const("Helpdesk", Module.new)
    stub_const("Helpdesk::Tools", Module.new)
    registry = stub_const("Helpdesk::Tool", Class.new(described_class))
    tool = stub_const("Helpdesk::Tools::Echo", Class.new(registry))
    tool.description "Return the supplied message."
    tool.schema { required(:message).filled(:string) }
    tool.define_method(:call) { message }

    definition = registry.resolve("echo")
    expect(definition.identifier).to eq("echo")
    expect(registry.identifiers([definition])).to eq(["echo"])
    expect(definition.call({ "message" => "Hello" }, context: nil).content).to eq("Hello")
  end
end
