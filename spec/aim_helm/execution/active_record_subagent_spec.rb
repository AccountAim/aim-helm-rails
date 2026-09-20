# frozen_string_literal: true

RSpec.describe "Active Record subagent execution" do
  let(:user) do
    email = "child-driver-#{SecureRandom.uuid_v7}@example.com"
    User.create!(organization: test_organization, name: "Child Driver User", email:)
  end

  let(:parent) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }
  let(:session) { AimHelmRails::Session.create!(actor: user, tenant: user.organization, parent_session: parent, name: "researcher") }

  let(:record) do
    AimHelm::Subagents::Record.new(
      session_id: session.id,
      parent_session_id: parent.id,
      run_id: "turn-1",
      parent_run_id: "parent-turn-1",
      call_id: "call-1",
      name: "researcher",
      task: "Research",
      mode: :background,
      options: AimHelm::Agent::Record.new(
        system: "Research carefully.",
        model: "gpt-5.6-luna",
      ),
    )
  end

  let(:aim_helm) { AimHelm.session(session.id) }

  before do
    allow(AimHelm.config.advance).to receive(:call)
    AimHelm::Control.new(session: AimHelm.session(parent.id)).start(
      prompt: "Delegate research",
      record: record.options,
      run_id: record.parent_run_id,
    )
    aim_helm.append(:spawn_record, record.dump, key: "spawn:turn-1", run_id: "turn-1")
    AimHelm::Control.new(session: aim_helm).start(
      prompt: record.task,
      record: record.options,
      run_id: record.run_id,
    )
  end

  it "fails closed when the queued grant differs from the durable spawn record" do
    other_parent = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    session.update!(parent_session: other_parent)

    expect do
      AimHelm.agent(session: aim_helm).advance(claimed_by: "worker-1")
    end.to raise_error(AimHelm::DispatchGrantError, /envelope differs from its spawn record/)
  end
end
