RSpec.describe AimHelmRails::Session, type: :model do
  let(:user) do
    User.create!(organization: test_organization, name: "Lease User",
                 email: "lease-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:session) { described_class.create!(actor: user, tenant: user.organization) }
  let(:now) { Time.current.change(usec: 0) }

  it "restores the persisted tenant after the actor changes organizations" do
    original_tenant = session.tenant
    expect(session.aim_helm_context).to eq(execution_context(user))

    user.update!(organization: Organization.create!(name: "Another organization"))

    expect(session.reload.aim_helm_context.tenant).to eq(original_tenant)
    expect(session.aim_helm_context.actor.organization).not_to eq(original_tenant)
  end

  it "projects chat history from durable run and provider-turn entries" do
    aim_helm = AimHelm.session(session.id)
    run_id = SecureRandom.uuid_v7
    turn_id = SecureRandom.uuid_v7
    aim_helm.append(
      :user,
      { content: [{ type: "text", text: "<user-message>Compare weekly traffic</user-message>" }] },
      run_id:,
    )
    aim_helm.append(
      :assistant,
      {
        content: [
          { type: "thinking", thinking: "Inspect the series" },
          { type: "text", text: "Traffic increased by 12%." },
        ],
      },
      run_id:,
      turn_id:,
    )
    aim_helm.append(
      :tool_call,
      { id: "call-1", name: "lake/query", arguments: {} },
      run_id:,
      turn_id:,
    )
    aim_helm.append(
      :tool_started,
      { call_id: "call-1", name: "lake/query" },
      run_id:,
      turn_id:,
    )
    aim_helm.append(
      :tool_result,
      {
        call_id: "call-1",
        error: false,
        output: "Displayed the card.",
        metadata: {
          resource: {
            gid: "report-1",
          },
        },
      },
      run_id:,
      turn_id:,
    )

    expect(session.reload.history_runs.fetch(0)).to include(assistant_timestamp: nil)

    terminal = aim_helm.append(
      :terminal,
      { outcome: :done },
      key: "terminal:#{run_id}",
      run_id:,
    )

    run = session.reload.history_runs.fetch(0)

    expect(session.title).to eq("Compare weekly traffic")
    expect(session.message_count).to eq(2)
    expect(run).to eq(
      run_id:,
      attachments: [],
      message: "Compare weekly traffic",
      items: [
        {
          type: "thinking",
          content: "Inspect the series",
          index: 0,
          turn_id:,
        },
        {
          type: "text",
          content: "Traffic increased by 12%.",
          index: 1,
          turn_id:,
        },
        {
          type: "tool",
          call_id: "call-1",
          name: "lake/query",
          arguments: {},
          preview: nil,
          status: "done",
          error: nil,
          turn_id:,
        },
        {
          type: "resource",
          gid: "report-1",
          id: "resource_#{Digest::SHA256.hexdigest("call-1:report-1")}",
          src: "/host/resources/report-1?frame=resource_#{Digest::SHA256.hexdigest("call-1:report-1")}",
          turn_id:,
        },
      ],
      user_timestamp: session.entries.find { |entry| entry.kind == "user" }.created_at.iso8601,
      assistant_timestamp: terminal.created_at.iso8601,
    )
  end

  it "projects a child run under its parent spawn tool" do
    child = described_class.create!(actor: user, tenant: user.organization,
                                    parent_session: session, name: "researcher")
    parent = AimHelm.session(session.id)
    child_session = AimHelm.session(child.id)
    parent_run_id = SecureRandom.uuid_v7
    parent_turn_id = SecureRandom.uuid_v7
    child_run_id = SecureRandom.uuid_v7
    child_followup_run_id = SecureRandom.uuid_v7
    child_tool_turn_id = SecureRandom.uuid_v7
    child_answer_turn_id = SecureRandom.uuid_v7
    child_followup_turn_id = SecureRandom.uuid_v7

    child_session.append(
      :user,
      { content: [{ type: "text", text: "<user-message>Write the story</user-message>" }] },
      run_id: child_run_id,
    )
    child_session.append(
      :assistant,
      { content: [{ type: "thinking", thinking: "Plan a small arc" }] },
      run_id: child_run_id,
      turn_id: child_tool_turn_id,
    )
    child_session.append(
      :tool_call,
      { id: "child-call-1", name: "tiles/render", arguments: {} },
      run_id: child_run_id,
      turn_id: child_tool_turn_id,
    )
    child_session.append(
      :tool_started,
      { call_id: "child-call-1", name: "tiles/render" },
      run_id: child_run_id,
      turn_id: child_tool_turn_id,
    )
    child_session.append(
      :tool_result,
      { call_id: "child-call-1", error: false, output: "Card shown" },
      run_id: child_run_id,
      turn_id: child_tool_turn_id,
    )
    child_session.append(
      :assistant,
      { content: [{ type: "text", text: "## The Lantern\n\nA short story." }] },
      run_id: child_run_id,
      turn_id: child_answer_turn_id,
    )
    child_terminal = child_session.append(
      :terminal,
      { outcome: :done },
      key: "terminal:#{child_run_id}",
      run_id: child_run_id,
    )
    child_session.append(
      :user,
      { content: [{ type: "text", text: "<user-message>What happened next?</user-message>" }] },
      run_id: child_followup_run_id,
    )
    child_session.append(
      :assistant,
      { content: [{ type: "text", text: "The lantern lit their home." }] },
      run_id: child_followup_run_id,
      turn_id: child_followup_turn_id,
    )
    child_followup_terminal = child_session.append(
      :terminal,
      { outcome: :done },
      key: "terminal:#{child_followup_run_id}",
      run_id: child_followup_run_id,
    )

    parent.append(
      :user,
      { content: [{ type: "text", text: "Delegate a story" }] },
      run_id: parent_run_id,
    )
    parent.append(
      :tool_call,
      { id: "spawn-1", name: "spawn_agent", arguments: {} },
      run_id: parent_run_id,
      turn_id: parent_turn_id,
    )
    parent.append(
      :tool_started,
      { call_id: "spawn-1", name: "spawn_agent" },
      run_id: parent_run_id,
      turn_id: parent_turn_id,
    )
    parent.append(
      :subagent,
      {
        id: child.id.to_s,
        name: "researcher",
        task: "Write the story",
        mode: "background",
        call_id: "spawn-1",
      },
      run_id: parent_run_id,
      turn_id: parent_turn_id,
    )

    item = session.reload.history_runs.sole.fetch(:items).find do |candidate|
      candidate.fetch(:type) == "subagent"
    end

    expect(item.except(:runs)).to eq(
      type: "subagent",
      call_id: "spawn-1",
      name: "researcher",
      session_id: child.id.to_s,
      task: "Write the story",
      turn_id: parent_turn_id,
    )
    child_runs = item.fetch(:runs)

    expect(child_runs.fetch(0)).to include(
      run_id: child_run_id,
      assistant_timestamp: child_terminal.created_at.iso8601,
      items: [
        {
          type: "thinking",
          content: "Plan a small arc",
          index: 0,
          turn_id: child_tool_turn_id,
        },
        {
          type: "tool",
          call_id: "child-call-1",
          name: "tiles/render",
          arguments: {},
          preview: nil,
          status: "done",
          error: nil,
          turn_id: child_tool_turn_id,
        },
        {
          type: "text",
          content: "## The Lantern\n\nA short story.",
          index: 0,
          turn_id: child_answer_turn_id,
        },
      ],
    )
    expect(child_runs.fetch(1)).to include(
      run_id: child_followup_run_id,
      message: "What happened next?",
      assistant_timestamp: child_followup_terminal.created_at.iso8601,
      items: [
        {
          type: "text",
          content: "The lantern lit their home.",
          index: 0,
          turn_id: child_followup_turn_id,
        },
      ],
    )
  end

  it "hides internal subagent reports from the projected parent conversation" do
    aim_helm = AimHelm.session(session.id)
    first_run_id = SecureRandom.uuid_v7
    report_run_id = SecureRandom.uuid_v7
    aim_helm.append(
      :user,
      { content: [{ type: "text", text: "<user-message>Research the topic</user-message>" }] },
      run_id: first_run_id,
    )
    report = AimHelm::Control.new(session: aim_helm).queue_message(
      content: "Sub-agent researcher finished: private report",
      type: :report,
      key: "report:child-1",
      subagent_session_id: "child-1",
    )
    aim_helm.append(
      :user,
      {
        content: report.payload.fetch("content"),
        covers_through_entry_id: report.id,
      },
      run_id: report_run_id,
    )
    aim_helm.append(
      :assistant,
      { content: [{ type: "text", text: "The research is ready." }] },
      run_id: report_run_id,
      turn_id: SecureRandom.uuid_v7,
    )

    projected = session.reload.history_runs

    expect(projected.fetch(1)).to include(
      run_id: report_run_id,
      message: nil,
      user_timestamp: nil,
    )
    expect(session.message_count).to eq(2)
  end

  it "acquires, heartbeats, and releases a lease on the sessions table" do
    lease = session.hold_lease(claimed_by: "worker-1", now:)

    expect(session.hold_lease(claimed_by: "worker-2", now:)).to be_nil
    expect(session.reload).to have_attributes(
      claimed_by: "worker-1",
      lease_token: lease.token,
      heartbeat_at: now,
    )
    expect(lease.heartbeat?(now: now + 20.seconds, interval: 0.seconds)).to be(true)
    expect(session.reload.heartbeat_at).to eq(now + 20.seconds)

    expect(lease.release(now: now + 22.seconds)).to be(true)
    expect(session.reload).to have_attributes(claimed_by: nil, lease_token: nil, heartbeat_at: nil)
  end
end
