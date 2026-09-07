# frozen_string_literal: true

RSpec.describe "Active Record subagent execution" do
  include Dry::Monads[:result]

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

  it "delivers one typed report through the parent's queued-message path" do
    message = AimHelm::Message.assistant(
      content: "Research complete",
      model: "gpt-5.6-luna",
      provider: :openai,
      usage: nil,
      stop_reason: :stop,
    )

    allow(AimHelm::Runner).to receive(:resume) do
      aim_helm.append(
        :assistant,
        {
          content: message.content,
          model: message.model,
          provider: message.provider,
          stop_reason: message.stop_reason,
        },
        run_id: "turn-1",
      )
      aim_helm.append(:terminal, { outcome: :done }, key: "terminal:turn-1", run_id: "turn-1")
      Success(AimHelm::Runner::Result.new(session: aim_helm, message:, run_id: "turn-1"))
    end

    AimHelm.agent(session: aim_helm).advance(claimed_by: "worker-1")

    report = AimHelm.session(parent.id).pending_messages.fetch(0)
    expect(report.payload).to include(
      "content" => [
        {
          "type" => "text",
          "text" => "Sub-agent researcher (#{session.id}) finished completed:\nResearch complete",
        },
      ],
      "type" => "report",
      "subagent_session_id" => session.id.to_s,
      "subagent_name" => "researcher",
      "subagent_status" => "completed",
    )
    expect(AimHelm.config.advance).to have_received(:call).with(parent.id)
  end

  it "fails closed when the queued grant differs from the durable spawn record" do
    other_parent = AimHelmRails::Session.create!(actor: user, tenant: user.organization)
    session.update!(parent_session: other_parent)

    expect do
      AimHelm.agent(session: aim_helm).advance(claimed_by: "worker-1")
    end.to raise_error(AimHelm::DispatchGrantError, /envelope differs from its spawn record/)
  end
end
