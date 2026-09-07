RSpec.describe AimHelmRails::Runtime do
  let(:tenant) { test_organization }
  let(:owner) { Organization.create!(name: "Owner actor") }
  let(:collaborator) { Organization.create!(name: "Collaborating actor") }
  let(:chat) { AimHelmRails::Session.create!(actor: owner, tenant:, helmsman: "probe") }

  before do
    definition = AimHelm.agent("gpt-5.6-luna")
    allow(AimHelmRails.host)
      .to receive(:helmsman).with("probe").and_return(double(agent: definition))
    allow(AimHelmRails.host).to receive(:authorize!)
    allow(AimHelm.config.advance).to receive(:call)
  end

  it "persists the initiating actor separately from chat ownership" do
    described_class.run(chat, "Read the report", actor: collaborator, tenant:)

    expect(chat.reload.actor).to eq(owner)
    expect(AimHelm.config.store.context(chat.id))
      .to eq(AimHelmRails::ExecutionContext.new(actor: collaborator, tenant:))
  end

  it "does not change the execution grant while a turn is pending" do
    described_class.run(chat, "Read the report", actor: owner, tenant:)

    expect { described_class.run(chat, "Change direction", actor: collaborator, tenant:) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(chat.reload.aim_helm_context.actor).to eq(owner)
    expect(chat.entries.where(kind: "queued_message")).to be_empty
  end

  it "enforces the tenant even when the host authorizes the actor" do
    other_tenant = Organization.create!(name: "Other tenant")

    expect { described_class.run(chat, "Read", actor: owner, tenant: other_tenant) }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(chat.entries).to be_empty
  end
end
