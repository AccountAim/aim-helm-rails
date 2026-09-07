# frozen_string_literal: true

RSpec.describe AimHelm::Subagents::Reaper do
  let(:user) do
    User.create!(organization: test_organization, name: "Retire User",
                 email: "retire-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:parent) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }

  before do
    allow(AimHelm.config.advance).to receive(:call)
  end

  it "stops only subagents marked with the interrupted spawn call" do
    child = running_child("child")
    unrelated = running_child("unrelated")
    aim_helm = AimHelm.session(parent.id)
    aim_helm.append(
      :subagent,
      { id: child.id, name: "child", task: "Work", mode: :background, call_id: "call-1" },
      run_id: "parent-turn-1",
    )
    aim_helm.append(
      :subagent,
      {
        id: unrelated.id,
        name: "unrelated",
        task: "Work",
        mode: :background,
        call_id: "call-2",
      },
      run_id: "parent-turn-1",
    )

    described_class.new(parent: aim_helm).call(
      tool_call: { "id" => "call-1", "name" => "spawn_agent", "arguments" => {} },
      entries: aim_helm.entries,
    )

    expect(AimHelm.session(child.id).entries.last).to have_attributes(
      kind: "stop_request",
      run_id: "child-turn-1",
    )
    expect(AimHelm.session(unrelated.id).entries.map(&:kind)).to eq(["user"])
    expect(AimHelm.config.advance).to have_received(:call).with(child.id.to_s)
    expect(AimHelm.config.advance).not_to have_received(:call).with(unrelated.id.to_s)
  end

  def running_child(name)
    AimHelmRails::Session.create!(actor: user, tenant: user.organization, parent_session: parent,
                                  name:).tap do |child|
      AimHelm.session(child.id).append(
        :user,
        { content: AimHelm::Message.user("Work").content },
        run_id: "child-turn-1",
      )
      child.hold_lease(claimed_by: "worker-#{name}")
      child.update!(status: "running")
    end
  end
end
