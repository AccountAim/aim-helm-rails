module AimHelmRails
  # Runs one queued root or subagent turn through AimHelm's durable worker.
  class AdvanceSessionJob < AimHelm::ActiveJob::AdvanceSessionJob
    self.enqueue_after_transaction_commit = true

    queue_as :agent
    limits_concurrency to: 1, key: ->(session_id, *) { session_id }, duration: 30.minutes

    after_discard do |_job, error|
      Rails.error.report(error, handled: true, severity: :error)
    end
  end
end
