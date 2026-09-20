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

  it "refuses an identifier nothing defines" do
    expect { described_class.resolve("nope") }.to raise_error(AimHelm::ConfigurationError)
  end

  it "serializes a bare hash or array result as JSON text" do
    expect(described_class.coerce({ "rows" => [1, 2] }).content).to eq('{"rows":[1,2]}')
    expect(described_class.coerce([1, 2]).content).to eq("[1,2]")
  end

  it "passes a finished result through" do
    result = AimHelm::Tool::Result.success(content: "done", metadata: { "n" => 1 })

    expect(described_class.coerce(result)).to equal(result)
  end
end
