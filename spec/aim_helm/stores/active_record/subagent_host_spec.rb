# frozen_string_literal: true

RSpec.describe AimHelm::Stores::ActiveRecord::SubagentHost do
  let(:user) do
    User.create!(organization: test_organization, name: "Child Host User",
                 email: "child-host-#{SecureRandom.uuid_v7}@example.com")
  end

  subject(:host) { AimHelm.config.store.subagent_host }

  before do
    allow(AimHelm.config.advance).to receive(:call)
  end

  it "persists a spawned subagent as a child row carrying the host identities" do
    parent = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    record = build_record(parent:, mode: :background)
    context = AimHelm::Tools::Context.new(
      session: AimHelm.session(parent.id),
      events: AimHelm::Tools::Broadcaster.new(sink: ->(_event) {}, call_id: record.call_id),
      app: execution_context(user),
      call_id: record.call_id,
      run_id: record.parent_run_id,
      turn_id: "parent-turn-1",
    )

    host.spawn(record:, context:)

    expect(AimHelmRails::Session.find(record.session_id)).to have_attributes(
      parent_session: parent,
      actor: user,
      tenant: user.organization,
      name: "researcher",
    )
  end

  it "raises a named error when an inline child's lease is already held" do
    parent = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    record = build_record(parent:, mode: :inline)
    child = AimHelmRails::Session.create!(id: record.session_id, actor: user,
                                          tenant: user.organization, parent_session: parent)
    events = AimHelm::Tools::Broadcaster.new(sink: ->(_event) {}, call_id: record.call_id)
    context = AimHelm::Tools::Context.new(
      session: AimHelm.session(parent.id),
      events:,
      app: execution_context(user),
      call_id: record.call_id,
      run_id: record.parent_run_id,
      turn_id: "parent-turn-1",
    )
    AimHelm::Control.new(session: AimHelm.session(child.id)).start_subagent(record:)
    allow(host).to receive(:persist).and_return(child)
    child.hold_lease(claimed_by: "other-worker")

    expect { host.spawn(record:, context:) }
      .to raise_error(AimHelm::InlineSubagentBusyError, /produced no terminal report/)
  end

  def build_record(parent:, mode:)
    options = AimHelm::Agent::Record.new(
      system: "Research carefully.",
      model: "gpt-5.6-luna",
    )
    AimHelm::Subagents::Record.new(
      session_id: SecureRandom.uuid_v7, parent_session_id: parent.id,
      run_id: SecureRandom.uuid_v7, parent_run_id: SecureRandom.uuid_v7,
      call_id: "call-1", name: "researcher", task: "Research", mode:, options:
    )
  end
end
