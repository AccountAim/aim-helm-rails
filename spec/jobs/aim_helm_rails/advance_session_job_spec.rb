RSpec.describe AimHelmRails::AdvanceSessionJob, type: :job do
  include Dry::Monads[:result]

  let(:user) do
    User.create!(organization: test_organization, name: "Job User",
                 email: "job-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:session) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }
  let(:aim_helm_session) { AimHelm.session(session.id) }
  let(:run_id) { SecureRandom.uuid_v7 }

  let(:options) do
    AimHelm::Agent.new(instructions: "Answer accurately.", model: "gpt-5.6-luna")
  end

  let(:record) { AimHelm::Agent::Record.capture(options:, tools: []) }

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  it "reconstructs and resumes the pending turn under its lease" do
    append_turn
    attributes = nil

    allow(AimHelm::Runner).to receive(:resume) do |**values|
      attributes = values
      Success(
        AimHelm::Runner::Result.new(
          session: aim_helm_session,
          message: AimHelm::Message.assistant(
            content: "Done",
            model: options.model,
            provider: :openai,
            usage: nil,
            stop_reason: :stop,
          ),
          run_id:,
        ),
      )
    end

    described_class.perform_now(session.id)

    expect(attributes).to include(app: execution_context(user), run_id:)
    expect(attributes.fetch(:session)).to have_attributes(id: session.id.to_s)
    expect(attributes.fetch(:options)).to have_attributes(
      instructions: options.instructions,
      model: options.model,
      tools: [],
    )
    expect(attributes.fetch(:emit)).to be_a(AimHelm::Events::LeasedSink)
    expect(attributes.fetch(:authorize)).to have_attributes(context: execution_context(user))
    expect(attributes.fetch(:on_interrupted_tool)).to have_attributes(parent: aim_helm_session)
    expect(session.reload).to have_attributes(
      claimed_by: nil,
      lease_token: nil,
      heartbeat_at: nil,
    )
  end

  it "does nothing while another worker owns the lease" do
    append_turn
    lease = session.hold_lease(claimed_by: "other-worker")
    allow(AimHelm::Runner).to receive(:resume)

    described_class.perform_now(session.id)

    expect(AimHelm::Runner).not_to have_received(:resume)
    expect(session.reload.lease_token).to eq(lease.token)
  end

  it "does nothing after the pending turn has a terminal" do
    append_turn
    aim_helm_session.append(
      :terminal,
      { outcome: :done },
      key: "terminal:#{run_id}",
      run_id:,
    )
    allow(AimHelm::Runner).to receive(:resume)

    described_class.perform_now(session.id)

    expect(AimHelm::Runner).not_to have_received(:resume)
    expect(session.reload.lease_token).to be_nil
  end

  it "discards a tampered record after writing a failed terminal" do
    aim_helm_session.append(:user, user_payload, key: "user:#{run_id}", run_id:)
    allow(Rails.error).to receive(:report)

    expect { described_class.perform_now(session.id) }.not_to raise_error

    terminal = aim_helm_session.entries.last
    expect(terminal).to have_attributes(kind: "terminal", key: "terminal:#{run_id}")
    expect(terminal.payload).to include(
      "outcome" => "failed",
      "reason" => "invalid_run_record",
      "error" => a_string_matching(/missing run record/),
    )
    expect(Rails.error).to have_received(:report).with(
      instance_of(AimHelm::TamperedRecordError),
      handled: true,
      severity: :error,
    )
  end

  it "completes normally when the runner returns a terminal failure" do
    append_turn

    allow(AimHelm::Runner).to receive(:resume) do
      aim_helm_session.append(
        :terminal,
        { outcome: :failed, reason: :max_iterations },
        key: "terminal:#{run_id}",
        run_id:,
      )
      Failure([:max_iterations, options.max_turns])
    end

    expect { described_class.perform_now(session.id) }.not_to raise_error
    expect(aim_helm_session.entries.count { |entry| entry.kind == "terminal" }).to eq(1)
  end

  it "retries transient errors and writes a terminal only on the final attempt" do
    append_turn
    allow(AimHelm::Runner).to receive(:resume)
      .and_raise(AimHelm::OverloadedError, "busy")
    job = described_class.new(session.id)

    4.times do
      expect { job.perform_now }.not_to raise_error
      expect(aim_helm_session.entries.map(&:kind)).not_to include("terminal")
    end

    expect { job.perform_now }.to raise_error(AimHelm::OverloadedError, "busy")
    expect(aim_helm_session.entries.last).to have_attributes(
      kind: "terminal",
      key: "terminal:#{run_id}",
      payload: {
        "outcome" => "failed",
        "reason" => "transient_error",
        "error" => "busy",
      },
    )
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(4)
  end

  def append_turn
    aim_helm_session.append(:run_record, record.dump, key: "run:#{run_id}", run_id:)
    aim_helm_session.append(:user, user_payload, key: "user:#{run_id}", run_id:)
  end

  def user_payload
    { content: AimHelm::Message.user("Summarize").content }
  end
end
