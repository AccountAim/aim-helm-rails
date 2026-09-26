RSpec.describe AimHelmRails::Features::Workspace::Adapters::ActiveRecord do
  subject(:workspace) { AimHelmRails::Features::Workspace.adapter(described_class.new(**scope)) }

  let(:scope) { { kind: :memory, tenant: test_organization } }

  it "scopes one path by tenant, actor, kind, and key" do
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

    product = described_class.new(tenant: test_organization, kind: :knowledge_base, key: :product)
    engineering = described_class.new(tenant: test_organization, kind: :knowledge_base,
                                      key: :engineering)
    product.write("profile.md", "Product")
    engineering.write("profile.md", "Engineering")

    expect(product.read("profile.md")).to eq("Product")
    expect(engineering.read("profile.md")).to eq("Engineering")
    expect(described_class.new(kind: :memory, tenant: test_organization).read("profile.md"))
      .to eq("Private to the first tenant")
  end

  it "reads but refuses every write when read-only" do
    described_class.new(**scope).write("profile.md", "Owner wrote this")
    guest = described_class.new(**scope).readonly

    expect(guest.read("profile.md")).to eq("Owner wrote this")
    expect { guest.write("profile.md", "x") }.to raise_error(AimHelmRails::Features::Workspace::ReadOnly)
    expect { guest.delete("profile.md") }.to raise_error(AimHelmRails::Features::Workspace::ReadOnly)
    expect { guest.compare_and_write("new.md", "x", expected_revision: nil) }
      .to raise_error(AimHelmRails::Features::Workspace::ReadOnly)
  end

  it "filters the listing by path prefix" do
    workspace.write("notes/plan.md", "Plan")
    workspace.write("profile.md", "Profile")

    expect(workspace.list("notes/")).to eq(["notes/plan.md"])
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
    rescue AimHelmRails::Features::Workspace::ConflictError => e
      e
    end

    expect(error.path).to eq("profile.md")
    expect(error.expected_revision).to eq(stale.revision)

    expect do
      workspace.compare_and_write("profile.md", "Four", expected_revision: nil)
    end.to raise_error(AimHelmRails::Features::Workspace::ConflictError)

    expect(workspace.read("profile.md")).to eq("Two")
  end
end
