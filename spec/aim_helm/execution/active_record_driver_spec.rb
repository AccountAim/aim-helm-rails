# frozen_string_literal: true

RSpec.describe AimHelm::Execution::Driver do
  include Dry::Monads[:result]

  let(:user) do
    User.create!(organization: test_organization, name: "Driver User",
                 email: "driver-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:record) do
    AimHelm::Agent::Record.new(system: "Answer accurately.", model: "gpt-5.6-luna")
  end

  let(:options) { record.materialize(tools: []) }

  before do
    allow(AimHelm.config.advance).to receive(:call)
  end

  it "re-dispatches a root session when a message lands under its lease" do
    session = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    aim_helm = start_session(session)

    allow(AimHelm::Runner).to receive(:resume) do
      AimHelm::Control.new(session: aim_helm).queue_message(content: "Follow up",
                                                            key: "message:1")
      aim_helm.append(:terminal, { outcome: :done }, key: "terminal:turn-1", run_id: "turn-1")
      Success(result(aim_helm, "turn-1"))
    end

    described_class.new(options:, binding: binding(aim_helm)).call

    expect(session.reload.lease_token).to be_nil
    expect(AimHelm.config.advance).to have_received(:call).with(session.id.to_s)
  end

  it "starts queued work from log status when the cache is stale" do
    session = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    aim_helm = start_session(session)
    aim_helm.append(:terminal, { outcome: :done }, key: "terminal:turn-1", run_id: "turn-1")
    AimHelm::Control.new(session: aim_helm).queue_message(content: "Follow up", key: "message:1")
    session.update_column(:status, "running")
    resumed_turn = nil

    allow(AimHelm::Runner).to receive(:resume) do |run_id:, **|
      resumed_turn = run_id
      aim_helm.append(:terminal, { outcome: :done }, key: "terminal:#{run_id}", run_id:)
      Success(result(aim_helm, run_id))
    end

    described_class.new(options:, binding: binding(aim_helm)).call

    expect(resumed_turn).not_to eq("turn-1")
    expect(aim_helm.pending_messages).to be_empty
  end

  def binding(session)
    AimHelm.config.store.bind(
      session:,
      claimed_by: "worker-1",
      final_attempt: false,
      config: AimHelm.config,
    )
  end

  def start_session(session)
    AimHelm.session(session.id).tap do |aim_helm|
      AimHelm::Control.new(session: aim_helm).start(
        prompt: "First",
        record:,
        run_id: "turn-1",
      )
    end
  end

  def result(session, run_id)
    AimHelm::Runner::Result.new(
      session:,
      run_id:,
      message: assistant_message,
    )
  end

  def assistant_message
    AimHelm::Message.assistant(
      content: "Done", model: options.model, provider: :openai, usage: nil, stop_reason: :stop,
    )
  end
end
