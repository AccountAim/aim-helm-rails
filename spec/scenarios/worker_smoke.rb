module AgentWorkerSmoke
  TIMEOUT = 60

  module_function

  def call
    tenant = Organization.create!(name: "Worker smoke tenant")
    user = create_user(tenant)
    session = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    run_id = start_stopped_turn(session)
    job = AimHelmRails::AdvanceSessionJob.set(queue: :agent_acceptance).perform_later(session.id)
    terminal = wait_for_terminal(session)
    verify_terminal!(terminal)
    print_result(job:, session:, run_id:, terminal:)
  ensure
    cleanup(session, user, tenant)
  end

  def create_user(tenant)
    User.create!(
      organization: tenant, name: "Agent Worker Smoke",
      email: "agent-worker-smoke-#{SecureRandom.uuid_v7}@example.com"
    )
  end

  def start_stopped_turn(session)
    run_id = SecureRandom.uuid_v7
    control = AimHelm::Control.new(session: AimHelm.session(session.id))

    AimHelmRails::Session.transaction do
      control.start(prompt: "Stop before provider work.", record: run_record, run_id:)
      control.stop
    end

    run_id
  end

  def run_record
    options = AimHelm::Agent.new(
      instructions: "Do not call a provider.",
      model: "gpt-5.6-luna",
    )
    AimHelm::Agent::Record.capture(options:, tools: [])
  end

  def verify_terminal!(terminal)
    expected = { "outcome" => "stopped", "reason" => "cancelled" }
    return if terminal.payload.slice(*expected.keys) == expected

    raise "unexpected worker terminal #{terminal.payload.inspect}"
  end

  def print_result(job:, session:, run_id:, terminal:)
    puts JSON.pretty_generate(
      job_id: job.job_id,
      queue_adapter: ActiveJob::Base.queue_adapter.class.name,
      queue_name: job.queue_name,
      session_id: session.id,
      run_id:,
      status: session.reload.status,
      terminal: terminal.payload,
    )
  end

  def cleanup(session, user, tenant)
    AimHelmRails::SessionEntry.where(session_id: session.id).delete_all if session
    session&.destroy!
    user&.destroy!
    tenant&.destroy!
  end

  def wait_for_terminal(session)
    aim_helm = AimHelm.session(session.id)
    aim_helm.wait(timeout: TIMEOUT, interval: 0.1)
    terminal = aim_helm.entries.reverse_each.find do |entry|
      entry.kind == "terminal"
    end
    return terminal if terminal

    raise "timed out waiting for worker session #{session.id}"
  end
end

AgentWorkerSmoke.call
