# frozen_string_literal: true

require File.join(
  Gem.loaded_specs.fetch("aim-helm").full_gem_path,
  "spec/support/subagent_host_contract",
)

RSpec.describe AimHelm::Stores::ActiveRecord::SubagentHost do
  include ActiveJob::TestHelper

  around do |example|
    provider_factory = AimHelm.config.provider_factory
    queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs

    AimHelm.configure do |config|
      config.provider_factory = lambda do |model, **|
        AimHelm::Providers::Fake.new(model:, turns: [{ text: "Child complete" }])
      end
    end

    example.run
  ensure
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = queue_adapter
    AimHelm.configure { |config| config.provider_factory = provider_factory }
  end

  let(:user) do
    User.create!(organization: test_organization, name: "Subagent Contract",
                 email: "subagent-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:parent_record) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }
  let(:parent_session) { AimHelm.session(parent_record.id) }
  let(:subagent_host) { AimHelm.config.store.subagent_host }
  let(:events) { [] }

  let(:parent_context) do
    AimHelm::Tools::Context.new(
      session: parent_session,
      events: AimHelm::Tools::Broadcaster.new(sink: events.method(:<<), call_id: "call-1"),
      app: execution_context(user),
      call_id: "call-1",
      run_id: "parent-run-1",
      turn_id: "parent-turn-1",
    )
  end

  let(:child_session) { ->(id) { AimHelm.session(id) } }

  let(:child_record) do
    lambda do |mode|
      AimHelm::Subagents::Record.new(
        session_id: SecureRandom.uuid_v7,
        parent_session_id: parent_session.id,
        run_id: SecureRandom.uuid_v7,
        parent_run_id: parent_context.run_id,
        call_id: parent_context.call_id,
        name: "researcher",
        task: "Research",
        mode:,
        options: AimHelm::Agent::Record.new(
          system: "Research carefully.",
          model: "gpt-5.6-luna",
        ),
      )
    end
  end

  let(:finish_background) do
    lambda do |record|
      job = enqueued_jobs.find { |candidate| candidate.fetch(:args).first == record.session_id }
      job_id = job.fetch("job_id")
      perform_enqueued_jobs(only: ->(candidate) { candidate.fetch("job_id") == job_id })
    end
  end

  it_behaves_like "a AimHelm subagent host"
end
