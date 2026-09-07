RSpec.describe AimHelmRails::Features::Workspace do
  let(:first_user) do
    User.create!(organization: test_organization, name: "First",
                 email: "first-workspace-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:second_user) do
    User.create!(organization: test_organization, name: "Second",
                 email: "second-workspace-#{SecureRandom.uuid_v7}@example.com")
  end

  before { described_class.register(AimHelmRails::Tool) }

  let(:memory_identifiers) do
    %w[workspace/memory/list workspace/memory/read workspace/memory/write
       workspace/memory/edit workspace/memory/search]
  end

  let(:knowledge_base_read_identifiers) do
    %w[workspace/knowledge_base/list workspace/knowledge_base/read
       workspace/knowledge_base/search]
  end

  let(:knowledge_base_write_identifiers) do
    %w[workspace/knowledge_base/list workspace/knowledge_base/read
       workspace/knowledge_base/write workspace/knowledge_base/edit
       workspace/knowledge_base/search]
  end

  it "registers every memory tool under a durable identifier" do
    identifiers = AimHelmRails::Tool.identifiers(described_class.memory_tools)

    expect(identifiers).to eq(memory_identifiers)
    expect(identifiers.map { AimHelmRails::Tool.resolve(it).name }).to eq(
      %w[memory_list memory_read memory_write memory_edit memory_search],
    )
  end

  it "builds read and write grants for the shared knowledge base" do
    read = described_class.knowledge_base_tools
    write = described_class.knowledge_base_tools(access: :write)

    expect(AimHelmRails::Tool.identifiers(read)).to eq(knowledge_base_read_identifiers)
    expect(AimHelmRails::Tool.identifiers(write)).to eq(knowledge_base_write_identifiers)
  end

  it "binds memory documents to the current user" do
    tools = described_class.memory_tools.index_by(&:name)
    first_context = Data.define(:app).new(app: execution_context(first_user))
    second_context = Data.define(:app).new(app: execution_context(second_user))

    tools.fetch("memory_write").call(
      { "path" => "profile.md", "content" => "First memory" }, context: first_context
    )
    tools.fetch("memory_write").call(
      { "path" => "profile.md", "content" => "Second memory" }, context: second_context
    )

    first = tools.fetch("memory_read").call({ "path" => "profile.md" }, context: first_context)
    second = tools.fetch("memory_read").call({ "path" => "profile.md" }, context: second_context)

    expect(first.content).to eq("1: First memory")
    expect(second.content).to eq("1: Second memory")
  end

  it "shares knowledge base documents between users" do
    tools = described_class.knowledge_base_tools(access: :write).index_by(&:name)
    first_context = Data.define(:app).new(app: execution_context(first_user))
    second_context = Data.define(:app).new(app: execution_context(second_user))

    tools.fetch("knowledge_base_write").call(
      { "path" => "product/metrics.md", "content" => "Shared definition" },
      context: first_context,
    )
    result = tools.fetch("knowledge_base_read").call(
      { "path" => "product/metrics.md" },
      context: second_context,
    )

    expect(result.content).to eq("1: Shared definition")
  end

  it "reconstructs workspace grants from durable identifiers" do
    allow(AimHelm.config.advance).to receive(:call)
    session = AimHelmRails::Session.create!(actor: first_user, tenant: first_user.organization,
                                            helmsman: "analyst")

    tools = described_class.memory_tools + described_class.knowledge_base_tools
    definition = AimHelm.agent("gpt-5.6-luna", tools:)
    allow(AimHelmRails.host)
      .to receive(:helmsman).with("analyst").and_return(double(agent: definition))
    AimHelmRails::Runtime.run(session, "Remember my reporting preference")

    rebuilt = AimHelm.agent(session: AimHelm.session(session.id))
    identifiers = rebuilt.tools.map(&:identifier)

    expect(identifiers).to include(*memory_identifiers, *knowledge_base_read_identifiers)
    expect(identifiers).not_to include(
      "workspace/knowledge_base/write",
      "workspace/knowledge_base/edit",
    )
  end
end
