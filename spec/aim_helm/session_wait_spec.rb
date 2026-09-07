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

  it "turns new input on a completed session into one follow-up turn" do
    control = AimHelm::Control.new(session:)
    control.start(prompt: "First", record:, run_id: "turn-1")
    session.append(:terminal, { outcome: :done }, key: "terminal:turn-1", run_id: "turn-1")
    model.update_column(:status, "running")

    AimHelm.agent(session:).run("Follow up")

    expect(model.reload.status).to eq("queued")
    expect(session.pending_messages).to be_empty
    expect(session.entries.last(2)).to match(
      [
        have_attributes(kind: "run_record", run_id: a_string_matching(/\A[0-9a-f-]+\z/)),
        have_attributes(
          kind: "user",
          payload: hash_including(
            "content" => [{ "type" => "text", "text" => "Follow up" }],
          ),
        ),
      ],
    )
    expect(AimHelm.config.advance).to have_received(:call).with(model.id.to_s)
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

  it "bounds waits and yields periodic activity" do
    expect { session.wait(timeout: 301) }
      .to raise_error(ArgumentError, /between 1 and 300 seconds/)

    allow(session).to receive(:status).and_return(:running, :completed)
    allow(session).to receive(:monotonic_time).and_return(0.0, 0.0, 31.0)
    allow(session).to receive(:sleep)
    activity = 0

    session.wait(timeout: 60) { activity += 1 }

    expect(activity).to eq(1)
  end
end
