# frozen_string_literal: true

RSpec.describe AimHelm::Session do
  let(:user) do
    User.create!(organization: test_organization, name: "Session User",
                 email: "session-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:record) do
    AimHelm::Agent::Record.new(system: "Answer accurately.", model: "gpt-5.6-luna")
  end

  let(:model) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }
  subject(:session) { AimHelm.session(model.id) }

  before do
    allow(AimHelm.config.advance).to receive(:call)
  end

  it "keeps new input durable without dispatching a parked session" do
    run_id = "turn-1"
    session.append(:run_record, record.dump, run_id:)
    session.append(:user, { content: "Run lookup" }, run_id:)
    session.append(
      :approval_request,
      { call_id: "call-1", name: "lookup", arguments: {}, title: "lookup" },
      run_id:,
    )

    AimHelm.agent(session:).run("Use the latest report")

    expect(session.status).to eq(:awaiting_approval)
    expect(session.pending_messages.map(&:payload)).to contain_exactly(
      include("content" => [{ "type" => "text", "text" => "Use the latest report" }]),
    )
    expect(AimHelm.config.advance).not_to have_received(:call)
  end
end
