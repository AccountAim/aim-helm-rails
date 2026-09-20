# frozen_string_literal: true

RSpec.describe AimHelmRails::HelmIntegration do
  let(:user) do
    User.create!(organization: test_organization, name: "Events User",
                 email: "events-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:record) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }
  let(:session) { AimHelm.session(record.id) }

  let(:event) do
    AimHelm::Event.build(type: :"run.queued").with(session_id: session.id, run_id: "run-1")
  end

  it "leaves Turbo Stream delivery and failure policy in the engine callback" do
    delivery = AimHelmRails::HelmIntegration::StreamedDelivery.new(
      event:, session:, context: execution_context(user), stream: "agent:#{record.id}",
    )
    error = IOError.new("cable unavailable")
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise(error)
    allow(Rails.error).to receive(:report)

    expect { described_class.broadcast(delivery) }.not_to raise_error
    expect(Rails.error).to have_received(:report).with(
      error,
      handled: true,
      severity: :warning,
      context: { agent_session_id: session.id },
    )
  end

  it "delivers child events to the root chat with their source session id" do
    child_record = AimHelmRails::Session.create!(actor: user, tenant: user.organization,
                                                 parent_session: record)
    child_session = AimHelm.session(child_record.id)
    child_event = AimHelm::Event.build(type: :"thinking.delta", delta: "Inspecting").with(
      session_id: child_session.id,
      run_id: "child-run-1",
      turn_id: "child-turn-1",
    )
    delivery = AimHelmRails::HelmIntegration::StreamedDelivery.new(
      event: child_event,
      session: child_session,
      context: execution_context(user),
      stream: "agent:#{record.id}",
    )
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

    described_class.broadcast(delivery)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
      "agent:#{record.id}",
      target: "agent-events-#{record.id}",
      partial: "aim_helm_rails/events/subscriber",
      locals: {
        event_type: :"thinking.delta",
        payload: { "delta" => "Inspecting" },
        run_id: "child-run-1",
        session_id: child_record.id.to_s,
        turn_id: "child-turn-1",
      },
    )
  end
end
