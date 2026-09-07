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

  it "persists and dispatches a background subagent envelope" do
    parent = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    record = build_record(parent:, mode: :background)
    events = []
    context = AimHelm::Tools::Context.new(
      session: AimHelm.session(parent.id),
      events: AimHelm::Tools::Broadcaster.new(sink: events.method(:<<), call_id: record.call_id),
      app: execution_context(user),
      call_id: record.call_id,
      run_id: record.parent_run_id,
      turn_id: "parent-turn-1",
    )

    result = host.spawn(record:, context:)

    child = AimHelmRails::Session.find(record.session_id)
    expect(result).to have_attributes(
      id: child.id.to_s,
      name: "researcher",
      status: :queued,
    )
    expect(child).to have_attributes(parent_session: parent, actor: user,
                                     tenant: user.organization, name: "researcher")
    expect(AimHelm.session(child.id).entries.map(&:kind)).to eq(
      %w[spawn_record run_record user],
    )
    expect(AimHelm.session(parent.id).entries.last).to have_attributes(
      kind: "subagent",
      payload: hash_including("id" => child.id.to_s, "mode" => "background"),
      turn_id: context.turn_id,
    )
    expect(events).to contain_exactly(
      have_attributes(
        type: :"subagent.spawned",
        call_id: record.call_id,
        name: record.name,
        payload: {
          "subagent_run_id" => record.run_id,
          "subagent_session_id" => record.session_id,
          "task" => record.task,
        },
      ),
    )
    expect(AimHelm.config.advance).to have_received(:call).with(child.id.to_s)
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

  it "emits wait activity through the calling tool context" do
    child = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    events = instance_double(AimHelm::Tools::Broadcaster, publish: nil)
    context = instance_double(AimHelm::Tools::Context, app: execution_context(user), events:)
    allow(host).to receive(:subagent_for).and_return(child)
    session = AimHelm.session(child.id)
    allow(host).to receive(:aim_helm_session).and_return(session)

    allow(session).to receive(:wait) do |**_arguments, &activity|
      activity.call
      session
    end

    result = host.read(id: child.id, wait: true, timeout: 300, context:)

    expect(result).to include(status: :empty)
    expect(events).to have_received(:publish).with(
      have_attributes(
        type: :"subagent.waiting",
        payload: { "subagent_session_id" => child.id.to_s },
      ),
    )
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
