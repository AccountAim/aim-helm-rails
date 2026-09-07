RSpec.describe "AimHelmRails::Session usage", type: :model do
  let(:user) do
    User.create!(organization: test_organization, name: "Usage User",
                 email: "usage-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:session) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }
  let(:run_id) { SecureRandom.uuid_v7 }

  def append_assistant(target, model:, **usage)
    counts = { input_tokens: 100, output_tokens: 20, cached_input_tokens: 0,
               cache_write_tokens: 0, reasoning_tokens: 0, cost: 0.001,
               wall_clock: 1.5 }.merge(usage)
    AimHelm.session(target.id).append(
      :assistant,
      { content: [{ type: "text", text: "ok" }], model:, provider: :openai, stop_reason: :stop,
        usage: counts.merge(model:) },
      run_id:,
    )
  end

  it "accounts for a chat and its subagent through the Active Record store" do
    child = AimHelmRails::Session.create!(actor: user, tenant: user.organization,
                                          parent_session: session, name: "researcher")
    append_assistant(session, model: "gpt-5.6-terra")
    AimHelm.session(session.id).append(
      :subagent,
      { "id" => child.id, "name" => child.name },
      run_id:,
    )
    append_assistant(child, model: "gpt-5.6-luna", input_tokens: 400, cost: 0.003)

    usage = session.usage
    expect(usage.steps.map(&:agent)).to eq([nil, "researcher"])
    expect(usage.total).to have_attributes(calls: 2, input: 500, cost: 0.004)
    expect(usage.by_model.map(&:model)).to contain_exactly("gpt-5.6-terra", "gpt-5.6-luna")
  end

  it "carries each provider call into the chat history" do
    append_assistant(session, model: "gpt-5.6-terra")

    items = session.history_runs.flat_map { |run| run[:items] }
    expect(items.select { |item| item[:type] == "usage" }.sole)
      .to include(model: "gpt-5.6-terra", input: 100, cost: 0.001)
  end
end
