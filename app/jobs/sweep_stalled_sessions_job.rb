module AimHelmRails
  # Recovers stale sessions and undelivered subagent reports from the recurring schedule.
  class SweepStalledSessionsJob < ApplicationJob
    queue_as :agent

    def perform = AimHelm.sweep
  end
end
