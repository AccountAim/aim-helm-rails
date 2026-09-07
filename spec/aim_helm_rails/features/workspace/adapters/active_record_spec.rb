require "rails_helper"

RSpec.describe AimHelmRails::Features::Workspace::Adapters::ActiveRecord do
  subject(:workspace) { AimHelm::Features::Workspace.adapter(described_class.new(**scope)) }

  let(:scope) { { kind: :memory, tenant: test_organization } }

  it "isolates both shared and personal documents between tenants" do
    actor = Organization.create!(name: "Actor")
    other_tenant = Organization.create!(name: "Other tenant")

    [nil, actor].each do |owner|
      first = described_class.new(kind: :memory, tenant: test_organization, actor: owner)
      second = described_class.new(kind: :memory, tenant: other_tenant, actor: owner)
      first.write("profile.md", "Private to the first tenant")

      expect(second.read("profile.md")).to be_nil
      second.write("profile.md", "Private to the second tenant")
      expect(first.read("profile.md")).to eq("Private to the first tenant")
    end
  end

  it "stores, lists, and deletes documents" do
    expect(workspace.read("notes/plan.md")).to be_nil

    workspace.write("notes/plan.md", "Plan")
    workspace.write("profile.md", "Profile")
    workspace.write("profile.md", "Updated profile")

    expect(workspace.read("notes/plan.md")).to eq("Plan")
    expect(workspace.read("profile.md")).to eq("Updated profile")
    expect(workspace.list).to eq(["notes/plan.md", "profile.md"])
    expect(workspace.list("notes/")).to eq(["notes/plan.md"])

    workspace.delete("notes/plan.md")

    expect(workspace.read("notes/plan.md")).to be_nil
  end

  it "keeps global and user workspaces separate" do
    user = User.create!(organization: test_organization, name: "Alice", email: "alice@example.com")
    global = AimHelm::Features::Workspace.adapter(described_class.new(tenant: test_organization,
                                                                      kind: :memory))
    personal = AimHelm::Features::Workspace.adapter(
      described_class.new(tenant: test_organization, kind: :memory, actor: user),
    )

    global.write("profile.md", "Shared")
    personal.write("profile.md", "Personal")

    expect(global.read("profile.md")).to eq("Shared")
    expect(personal.read("profile.md")).to eq("Personal")
  end

  it "keeps kinds and keys separate" do
    memory = AimHelm::Features::Workspace.adapter(described_class.new(tenant: test_organization,
                                                                      kind: :memory))
    product = AimHelm::Features::Workspace.adapter(
      described_class.new(tenant: test_organization, kind: :knowledge_base, key: :product),
    )
    engineering = AimHelm::Features::Workspace.adapter(
      described_class.new(tenant: test_organization, kind: :knowledge_base, key: :engineering),
    )

    memory.write("index.md", "Memory")
    product.write("index.md", "Product")
    engineering.write("index.md", "Engineering")

    expect(memory.read("index.md")).to eq("Memory")
    expect(product.read("index.md")).to eq("Product")
    expect(engineering.read("index.md")).to eq("Engineering")
  end

  it "conditionally replaces the revision it read" do
    created = workspace.compare_and_write("profile.md", "One", expected_revision: nil)
    current = workspace.snapshot("profile.md")

    expect(current).to eq(created)

    replaced = workspace.compare_and_write(
      "profile.md",
      "Two",
      expected_revision: current.revision,
    )

    expect(replaced.content).to eq("Two")
    expect(replaced.revision).not_to eq(current.revision)
  end

  it "rejects stale and duplicate conditional writes" do
    stale = workspace.compare_and_write("profile.md", "One", expected_revision: nil)
    workspace.compare_and_write("profile.md", "Two", expected_revision: stale.revision)

    error = begin
      workspace.compare_and_write("profile.md", "Three", expected_revision: stale.revision)
    rescue AimHelm::Features::Workspace::ConflictError => e
      e
    end

    expect(error.path).to eq("profile.md")
    expect(error.expected_revision).to eq(stale.revision)

    expect do
      workspace.compare_and_write("profile.md", "Four", expected_revision: nil)
    end.to raise_error(AimHelm::Features::Workspace::ConflictError)

    expect(workspace.read("profile.md")).to eq("Two")
  end
end
