RSpec.describe AimHelmRails::SweepStalledSessionsJob, type: :job do
  let(:user) do
    User.create!(organization: test_organization, name: "Sweeper User",
                 email: "sweeper-#{SecureRandom.uuid_v7}@example.com")
  end

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  it "advances stale queued, unowned running, and expired running sessions" do
    stale = Time.current - AimHelm::Stores::ActiveRecord::STALE_AFTER - 1.minute
    stale_queued = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    stale_queued.update_column(:updated_at, stale)
    unowned_running = AimHelmRails::Session.create!(actor: user, tenant: user.organization,
                                                    status: "running", heartbeat_at: nil)
    expired_running = AimHelmRails::Session.create!(actor: user, tenant: user.organization,
                                                    status: "running", heartbeat_at: stale)
    AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    AimHelmRails::Session.create!(actor: user, tenant: user.organization, status: "running",
                                  heartbeat_at: Time.current)
    awaiting = AimHelmRails::Session.create!(actor: user, tenant: user.organization,
                                             status: "awaiting_approval")
    awaiting.update_column(:updated_at, stale)
    parent = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    inline = stale_child(parent:, mode: :inline, heartbeat_at: stale)
    background = stale_child(parent:, mode: :background, heartbeat_at: stale)
    allow(AimHelm.config.advance).to receive(:call)

    described_class.perform_now

    [stale_queued, unowned_running, expired_running, background].each do |session|
      expect(AimHelm.config.advance).to have_received(:call).with(session.id.to_s).once
    end

    expect(AimHelm.config.advance).not_to have_received(:call).with(inline.id.to_s)
    expect(AimHelm.config.advance).to have_received(:call).exactly(4).times
  end

  it "recovers a terminal child before its report was appended" do
    parent = completed_parent
    child = completed_child(parent:)

    described_class.perform_now

    report = child_report(child)
    expect(report_entries(parent, report).size).to eq(1)
    expect(AimHelmRails::AdvanceSessionJob).to have_been_enqueued.with(parent.id)
  end

  it "recovers a report appended before its parent wake" do
    parent = completed_parent
    child = completed_child(parent:)
    report = child_report(child)
    queue_report(parent, report)

    described_class.perform_now

    expect(report_entries(parent, report).size).to eq(1)
    expect(AimHelm.session(parent.id).pending_messages).to be_empty
    expect(AimHelmRails::AdvanceSessionJob).to have_been_enqueued.with(parent.id)
  end

  it "recovers a folded report whose enqueue was lost" do
    parent = completed_parent
    child = completed_child(parent:)
    report = child_report(child)
    queue_report(parent, report)
    control = AimHelm::Control.new(session: AimHelm.session(parent.id))
    control.continue_queued(run_id: SecureRandom.uuid_v7)
    parent.update_column(
      :updated_at,
      Time.current - AimHelm::Stores::ActiveRecord::STALE_AFTER - 1.minute,
    )

    described_class.perform_now

    expect(report_entries(parent, report).size).to eq(1)
    expect(AimHelmRails::AdvanceSessionJob).to have_been_enqueued.with(parent.id)
  end

  it "derives background delivery from logs after a portable candidate query" do
    parent = completed_parent
    background = completed_child(parent:)
    inline = completed_child(parent:, mode: :inline)

    described_class.perform_now

    expect(report_entries(parent, child_report(background)).size).to eq(1)
    expect(report_entries(parent, child_report(inline))).to be_empty
    sql = AimHelm.config.store.terminal_subagents.to_sql
    expect(sql).not_to match(/->>|::/)
  end

  def stale_child(parent:, mode:, heartbeat_at:)
    child = AimHelmRails::Session.create!(actor: user, tenant: user.organization,
                                          parent_session: parent)
    record = spawn_record(child:, parent:, mode:)
    AimHelm.session(child.id).append(:spawn_record, record.dump, run_id: record.run_id)
    child.update!(status: "running", heartbeat_at:)
    child
  end

  def spawn_record(child:, parent:, mode:)
    AimHelm::Subagents::Record.new(
      session_id: child.id, parent_session_id: parent.id,
      run_id: SecureRandom.uuid_v7, parent_run_id: SecureRandom.uuid_v7,
      call_id: SecureRandom.uuid_v7, name: "researcher",
      task: "Research", mode:,
      options: AimHelm::Agent::Record.new(system: "Research.", model: "gpt-5.6-luna")
    )
  end

  def completed_parent
    parent = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    aim_helm = AimHelm.session(parent.id)
    run_id = SecureRandom.uuid_v7
    record = AimHelm::Agent::Record.new(system: "Research.", model: "gpt-5.6-luna")
    aim_helm.append(:run_record, record.dump, key: "run:#{run_id}", run_id:)
    aim_helm.append(:user, { content: "Research" }, run_id:)
    aim_helm.append(:terminal, { outcome: :done }, key: "terminal:#{run_id}", run_id:)
    parent
  end

  def completed_child(parent:, mode: :background)
    child = AimHelmRails::Session.create!(actor: user, tenant: user.organization,
                                          parent_session: parent, name: "researcher")
    record = spawn_record(child:, parent:, mode:)
    aim_helm = AimHelm.session(child.id)
    append_spawn(aim_helm, record)
    append_child_result(aim_helm, record.run_id)
    child
  end

  def append_spawn(aim_helm, record)
    aim_helm.append(
      :spawn_record,
      record.dump,
      key: "spawn:#{record.run_id}",
      run_id: record.run_id,
    )
  end

  def append_child_result(aim_helm, run_id)
    append_child_message(aim_helm, run_id)
    aim_helm.append(
      :terminal,
      { outcome: :done },
      key: "terminal:#{run_id}",
      run_id:,
    )
  end

  def append_child_message(aim_helm, run_id)
    payload = {
      content: "Research complete",
      model: "gpt-5.6-luna",
      provider: :openai,
      stop_reason: :stop,
    }
    aim_helm.append(:assistant, payload, run_id:)
  end

  def child_report(child)
    entries = AimHelm.session(child.id).entries
    record = AimHelm::Subagents::Record.latest(entries)
    AimHelm::Subagents::Report.from(entries:, record:)
  end

  def queue_report(parent, report)
    AimHelm::Control.new(session: AimHelm.session(parent.id)).queue_message(
      content: report.message,
      type: :report,
      key: "report:#{report.terminal_entry_id}",
    )
  end

  def report_entries(parent, report)
    AimHelm.session(parent.id).entries.select do |entry|
      entry.key == "report:#{report.terminal_entry_id}"
    end
  end
end
