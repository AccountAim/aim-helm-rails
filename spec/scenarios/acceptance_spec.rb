module AimHelmRails
  module Tools
    module Acceptance
      PUBLISH_SCHEMA = AimHelm::Schema.define do
        required(:value).filled(:string)
      end

      Publish = AimHelm::Tool.define(
        "publish_value",
        "Publishes one reviewed value.",
        identifier: "acceptance/publish",
        schema: PUBLISH_SCHEMA,
        needs_approval: true,
      ) { |arguments, _context| "published #{arguments.fetch("value")}" }
    end
  end
end

RSpec.describe "Agent acceptance scenarios" do
  include ActiveJob::TestHelper

  around do |example|
    provider_factory = AimHelm.config.provider_factory
    broadcast = AimHelm.config.broadcast

    AimHelm.configure do |config|
      config.broadcast = lambda do |delivery|
        @events << [delivery.session.id, delivery.event]
      end
    end

    example.run
  ensure
    AimHelm.configure do |config|
      config.provider_factory = provider_factory
      config.broadcast = broadcast
    end
  end

  before do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    # Core event delivery closes before examples inspect this cross-thread sink.
    @events = []
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  it "persists image input and a Dry::Schema result through a complete turn" do
    result_schema = AimHelm::Schema.define do
      required(:marker).filled(:string, eql?: "RUDDER VISION 42")
      required(:description).filled(:string)
    end
    provider = fake_provider(
      text: JSON.generate(marker: "RUDDER VISION 42", description: "Three colored shapes."),
    )
    use_providers("gpt-5.6-luna" => provider)
    prompt = [image_block, { type: "text", text: "Describe the image and return its marker." }]
    agent = AimHelm::Agent.new(
      instructions: "Inspect the supplied image.",
      model: "gpt-5.6-luna",
      output: result_schema,
    )

    session = start(prompt:, agent:)
    perform_session(session)

    expect(status(session)).to eq("completed")
    expect(result_schema.call(JSON.parse(assistant_text(session)))).to be_success
    request = provider.requests.sole
    expect(request.fetch(:messages).first.content.first).to eq(image_block.deep_stringify_keys)
    expect(request.fetch(:output_schema)).to eq(result_schema.json_schema.deep_stringify_keys)
    expect_reserved_events(
      session,
      :"run.queued",
      :"run.started",
      :"usage.reported",
      :"turn.completed",
      :"run.completed",
    )
    expect_event_log_alignment(session)
  end

  it "validates structured output on the queued job path" do
    result_schema = AimHelm::Schema.define do
      required(:answer).filled(:string, eql?: "ready")
      required(:values).value(:array, size?: 3).each(:integer)
    end
    provider = fake_provider(text: JSON.generate(answer: "ready", values: [2, 4, 6]))
    use_providers("gpt-5.6-luna" => provider)
    agent = AimHelm::Agent.new(
      instructions: "Return the requested data.",
      model: "gpt-5.6-luna",
      output: result_schema,
    )

    session = start(prompt: "Return ready and 2, 4, 6.", agent:)
    perform_session(session)

    result = result_schema.call(JSON.parse(assistant_text(session)))
    expect(result).to be_success
    expect(result.to_h).to eq(answer: "ready", values: [2, 4, 6])
    expect(provider.requests.sole.fetch(:output_schema))
      .to eq(result_schema.json_schema.deep_stringify_keys)
    expect_event_log_alignment(session)
  end

  it "re-agent a failed terminal session without resetting its lifetime spend" do
    first_provider = fake_provider(
      text: "I will remember cedar-17.",
      usage: { input_tokens: 3, output_tokens: 2 },
      model: "gpt-5.6-luna",
    )
    result_schema = AimHelm::Schema.define do
      required(:codeword).filled(:string, eql?: "cedar-17")
    end
    second_provider = fake_provider(
      text: JSON.generate(codeword: "cedar-17"),
      usage: { input_tokens: 2, output_tokens: 1 },
      model: "gpt-5.6-terra",
    )
    use_providers(
      "gpt-5.6-luna" => first_provider,
      "gpt-5.6-terra" => second_provider,
    )
    first_agent = AimHelm::Agent.new(
      instructions: "Remember supplied facts.",
      model: "gpt-5.6-luna",
      budget: AimHelm::Budget.new(tokens: 5),
    )
    second_agent = AimHelm::Agent.new(
      instructions: "Recover facts from the transcript.",
      model: "gpt-5.6-terra",
      budget: AimHelm::Budget.new(tokens: 20),
      output: result_schema,
    )

    session = start(
      prompt: "Remember that the codeword is cedar-17.",
      agent: first_agent,
    )
    perform_session(session)

    expect(status(session)).to eq("failed")
    expect(entries(session).last.payload).to include("reason" => "budget_exhausted")

    run(session, "Return the codeword from the earlier turn.", agent: second_agent)
    perform_session(session)

    expect(status(session)).to eq("completed")
    expect(result_schema.call(JSON.parse(assistant_text(session)))).to be_success
    expect(run_records(session).map(&:model)).to eq(%w[gpt-5.6-luna gpt-5.6-terra])
    replay_text = request_text(second_provider.requests.sole)
    expect(replay_text).to include("cedar-17", "Return the codeword")
    expect(event_types(session)).to include(:"run.failed", :"run.completed")
    expect_event_log_alignment(session)
  end

  it "parks a gated tool, persists one allow rule, and applies it on the next session" do
    provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-luna",
      turns: [
        tool_turn("publish_value", { value: "reviewed-42" }, id: "publish-1"),
        { text: "Published reviewed-42." },
        tool_turn("publish_value", { value: "reviewed-43" }, id: "publish-2"),
        { text: "Published reviewed-43." },
      ],
    )
    use_providers("gpt-5.6-luna" => provider)
    tool = AimHelmRails::Tools::Acceptance::Publish
    agent = AimHelm::Agent.new(
      instructions: "Publish the requested value once.",
      model: "gpt-5.6-luna",
      tools: [tool],
    )

    first = start(prompt: "Publish reviewed-42.", agent:)
    perform_session(first)

    expect(status(first)).to eq("awaiting_approval")
    request = entries(first).find { |entry| entry.kind == "approval_request" }
    decision = AimHelmRails::Runtime.decide(
      session: first,
      call_id: request.payload.fetch("call_id"),
      verdict: :approve,
      actor: user, tenant: user.organization,
      always_allow: true
    )
    duplicate = AimHelmRails::Runtime.decide(
      session: first,
      call_id: request.payload.fetch("call_id"),
      verdict: :approve,
      actor: user, tenant: user.organization,
      always_allow: true
    )
    expect(decision).to be_a(AimHelm::Session::Record)
    expect(duplicate).to be_nil
    rules = AimHelmRails::AllowRule.within(user.organization).by(user)
    expect(rules.where(tool_name: "acceptance/publish").count).to eq(1)

    perform_session(first)
    expect(status(first)).to eq("completed")
    expect(tool_results(first).sole.payload.fetch("output")).to eq("published reviewed-42")

    second = start(prompt: "Publish reviewed-43.", agent:)
    perform_session(second)

    expect(status(second)).to eq("completed")
    second_request = entries(second).find { |entry| entry.kind == "approval_request" }
    second_decision = entries(second).find { |entry| entry.kind == "approval_decision" }
    expect(second_request.payload.fetch("call_id")).to eq("publish-2")
    expect(second_decision.payload).to include(
      "call_id" => "publish-2",
      "source" => "rule",
    )
    expect(tool_results(second).sole.payload.fetch("output")).to eq("published reviewed-43")
    expect(event_types(first)).to include(:"tool.approval", :"run.completed")
    expect_event_log_alignment(first, second)
  end

  it "stops before provider work and records one stopped terminal" do
    session = start(prompt: "Do not execute this turn.", agent: worker_agent)

    AimHelmRails::Runtime.stop(session:, actor: user, tenant: user.organization)
    perform_session(session)
    perform_session(session)

    expect(status(session)).to eq("stopped")
    expect(terminals(session).sole.payload).to include(
      "outcome" => "stopped",
      "reason" => "cancelled",
    )
    expect(event_types(session)).to include(:"run.stopped")
    expect_event_log_alignment(session)
  end

  it "records a provider failure as a model outcome without duplicating its terminal" do
    provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-luna",
      turns: [{ error: "provider unavailable" }],
    )
    use_providers("gpt-5.6-luna" => provider)
    session = start(prompt: "Answer once.", agent: worker_agent)

    perform_session(session)
    AimHelmRails::Runtime.advance(session:, actor: user, tenant: user.organization)
    perform_session(session)

    expect(status(session)).to eq("failed")
    expect(terminals(session).sole.payload).to include(
      "outcome" => "failed",
      "reason" => "provider_error",
      "error" => "provider unavailable",
    )
    expect(event_types(session)).to include(:"provider.failed", :"run.failed")
    expect_event_log_alignment(session)
  end

  it "runs a general child inline and returns its report to the parent tool call" do
    provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-luna",
      turns: [
        tool_turn(
          "spawn_agent",
          {
            name: "greeter",
            task: "Confirm delegation worked.",
            instructions: "Answer briefly and include CHILD-READY.",
            mode: "inline",
          },
          id: "spawn-inline",
        ),
        { text: "CHILD-READY" },
        { text: "The child reported CHILD-READY." },
      ],
    )
    use_providers("gpt-5.6-luna" => provider)
    agent = AimHelm::Agent.new(
      instructions: "Delegate the task and report the inline result.",
      model: "gpt-5.6-luna",
      subagents: [AimHelm::Subagent.open(tools: [])],
    )

    parent = start(prompt: "Delegate the greeting.", agent:)
    perform_session(parent)

    child = parent.child_sessions.sole
    spawn = AimHelm::Subagents::Record.latest(entries(child))
    report = JSON.parse(tool_results(parent).sole.payload.fetch("output"))
    expect(status(parent)).to eq("completed")
    expect(status(child)).to eq("completed")
    expect(spawn).to have_attributes(name: "greeter", mode: :inline)
    expect(report).to include(
      "id" => child.id.to_s,
      "name" => "greeter",
      "status" => "completed",
      "text" => "CHILD-READY",
    )
    expect_reserved_events(child, :"run.started", :"run.completed")
    expect_event_log_alignment(parent, child)
  end

  it "steers, resumes, and receives late reports from one background specialist" do
    specialist = AimHelm::Subagent.new(
      name: "ledger_specialist",
      description: "Checks ledger arithmetic.",
      system: "Compute ledger balances and show the arithmetic.",
      model: "gpt-5.6-luna",
      tools: [],
    )
    parent_provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-terra",
      turns: [
        tool_turn(
          "spawn_agent",
          { agent: specialist.name, task: "Calculate 1200 + 350 - 90.", mode: "background" },
          id: "spawn-ledger",
        ),
        { text: "The specialist is running in the background." },
        { text: "The specialist reported a balance of 1460 and retained its context." },
      ],
    )
    child_provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-luna",
      turns: [
        { text: "1200 + 350 - 90 = 1460. STEERED-DETAIL included." },
        { text: "The earlier computed balance was 1460." },
      ],
    )
    use_providers(
      "gpt-5.6-terra" => parent_provider,
      "gpt-5.6-luna" => child_provider,
    )
    agent = AimHelm::Agent.new(
      instructions: "Delegate ledger work and consume later reports.",
      model: "gpt-5.6-terra",
      subagents: [specialist],
    )

    parent = start(prompt: "Start the ledger specialist in the background.", agent:)
    perform_session(parent)
    child = parent.child_sessions.sole
    spawn = AimHelm::Subagents::Record.latest(entries(child))

    # The spawn call carries no result yet, so the parent's turn is parked on its specialist.
    expect(status(parent)).to eq("awaiting_subagent")
    expect(terminals(parent)).to be_empty
    expect(status(child)).to eq("queued")
    expect(spawn).to have_attributes(name: specialist.name, mode: :background)
    expect(spawn.options).to have_attributes(
      system: specialist.system,
      model: specialist.model,
      tools: specialist.tools,
    )

    run(child, "Show the arithmetic and include STEERED-DETAIL.")
    perform_session(child)

    first_child_terminal = terminals(child).sole
    expect(AimHelm.session(child.id).pending_messages).to be_empty
    first_child_request = request_text(child_provider.requests.first)
    expect(first_child_request).to include("Calculate 1200", "STEERED-DETAIL")

    # The child's report answered the parked call, so the parent's own turn carries on.
    perform_session(parent)

    expect(terminals(parent).sole.created_at).to be > first_child_terminal.created_at
    expect(status(parent)).to eq("completed")
    expect(request_text(parent_provider.requests.second)).to include("1460")

    run(child, "What balance did you compute in your earlier task?")
    # A stale child wake is consumed before the continuation job.
    perform_until_settled(child)

    expect(status(child)).to eq("completed")
    expect(terminals(child).count).to eq(2)
    expect(entries(child).count { |entry| entry.kind == "spawn_record" }).to eq(2)
    expect(request_text(child_provider.requests.second))
      .to include("1460", "What balance did you compute")

    perform_session(parent)

    expect(status(parent)).to eq("completed")
    expect(terminals(parent).count).to eq(2)
    # The first report answered the parked spawn call; the late one starts a run of its own.
    answers = entries(parent).select do |entry|
      entry.kind == "tool_result" && entry.payload.fetch("call_id") == "spawn-ledger"
    end
    reports = entries(parent).select do |entry|
      entry.kind == "queued_message" && entry.payload.fetch("type") == "report"
    end
    expect(answers.count).to eq(1)
    expect(reports.count).to eq(1)
    expect(request_text(parent_provider.requests.third)).to include("1460")
    expect_event_log_alignment(parent, child)
  end

  it "parks and resumes approval-gated tools inside a background subagent" do
    publish = AimHelmRails::Tools::Acceptance::Publish
    allow(publish).to receive(:call).and_call_original
    specialist = AimHelm::Subagent.new(
      name: "publishing_specialist",
      description: "Publishes reviewed values.",
      system: "Request both publishes, then report their outcomes.",
      model: "gpt-5.6-luna",
      tools: [publish.identifier],
      modes: [:background],
    )
    parent_provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-terra",
      turns: [
        tool_turn(
          "spawn_agent",
          {
            agent: specialist.name,
            task: "Publish child-approved-42 and child-denied-42.",
            mode: "background",
          },
          id: "spawn-publisher",
        ),
        { text: "The publishing specialist is running." },
        { text: "The publishing specialist reported its reviewed outcomes." },
      ],
    )
    child_provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-luna",
      turns: [
        {
          tool_calls: [
            {
              id: "child-approved",
              name: "publish_value",
              arguments: { value: "child-approved-42" },
            },
            {
              id: "child-denied",
              name: "publish_value",
              arguments: { value: "child-denied-42" },
            },
          ],
        },
        { text: "Published child-approved-42; child-denied-42 was denied." },
      ],
    )
    use_providers(
      "gpt-5.6-terra" => parent_provider,
      "gpt-5.6-luna" => child_provider,
    )
    agent = AimHelm::Agent.new(
      instructions: "Delegate both reviewed publishes and consume the eventual report.",
      model: "gpt-5.6-terra",
      tools: [publish],
      subagents: [specialist],
    )

    parent = start(prompt: "Start the publishing specialist.", agent:)
    perform_session(parent)
    child = parent.child_sessions.sole
    perform_session(child)

    child_entries = entries(child)
    approvals = child_entries.select { |entry| entry.kind == "approval_request" }
    child_run_id = approvals.first.run_id
    expect(status(parent)).to eq("awaiting_subagent")
    expect(status(child)).to eq("awaiting_approval")
    expect(approvals.map { |entry| entry.payload.fetch("call_id") })
      .to contain_exactly("child-approved", "child-denied")
    expect(tool_results(child)).to be_empty
    expect(terminals(child)).to be_empty
    expect(AimHelm.session(parent.id).pending_messages).to be_empty
    expect(publish).not_to have_received(:call)
    expect(root_job_count).to eq(0)

    decision = AimHelmRails::Runtime.decide(
      session: child,
      call_id: "child-approved",
      verdict: :approve,
      actor: user, tenant: user.organization
    )
    duplicate = AimHelmRails::Runtime.decide(
      session: child,
      call_id: "child-approved",
      verdict: :approve,
      actor: user, tenant: user.organization
    )

    expect(decision).to be_a(AimHelm::Session::Record)
    expect(duplicate).to be_nil
    expect(session_job_count(child)).to eq(1)
    expect(root_job_count).to eq(0)

    AimHelmRails::Runtime.decide(
      session: child,
      call_id: "child-denied",
      verdict: :deny,
      actor: user, tenant: user.organization
    )
    expect(session_job_count(child)).to eq(2)
    expect(root_job_count).to eq(0)
    expect(event_types(child).count(:"tool.approval")).to eq(2)
    expect(event_types(child).count(:"tool.approved")).to eq(1)
    expect(event_types(child).count(:"tool.denied")).to eq(1)

    perform_session(child)

    results = tool_results(child).index_by { |entry| entry.payload.fetch("call_id") }
    expect(status(child)).to eq("completed")
    expect(terminals(child).sole.run_id).to eq(child_run_id)
    expect(results.fetch("child-approved").payload).to include(
      "output" => "published child-approved-42",
      "error" => false,
    )
    expect(results.fetch("child-denied").payload).to include(
      "output" => "The user denied this tool call.",
      "error" => true,
    )
    expect(request_text(child_provider.requests.second))
      .to include("published child-approved-42", "The user denied this tool call.")
    expect(publish).to have_received(:call).once
    expect(status(parent)).to eq("queued")
    expect(entries(parent).count { |entry| entry.key&.start_with?("report:") }).to eq(1)
    expect(AimHelm.session(parent.id).pending_messages).to be_empty
    expect(root_job_count).to eq(1)

    perform_session(child)

    answers = entries(parent).select { |entry| entry.kind == "tool_result" }
    expect(status(child)).to eq("completed")
    expect(terminals(child).count).to eq(1)
    # The report answered the spawn call the parent parked on.
    expect(answers.sole.payload).to include(
      "call_id" => "spawn-publisher",
      "output" => a_string_including("Published child-approved-42"),
    )
    expect(publish).to have_received(:call).once
    expect(root_job_count).to eq(1)

    perform_session(parent)

    expect(status(parent)).to eq("completed")
    expect(terminals(parent).count).to eq(1)
    expect(AimHelm.session(parent.id).pending_messages).to be_empty
    # One parent turn, resumed: the report arrived inside it rather than starting another.
    expect(request_text(parent_provider.requests.second)).to include("child-approved-42")
    expect_event_log_alignment(parent, child)
  end

  it "keeps a child report behind approval and folds it after the decision" do
    publish = AimHelmRails::Tools::Acceptance::Publish
    worker = AimHelm::Subagent.new(
      name: "reporter",
      description: "Produces the requested report.",
      system: "Return the requested report marker.",
      model: "gpt-5.6-luna",
      tools: [],
    )
    parent_provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-terra",
      turns: [
        {
          tool_calls: [
            {
              id: "spawn-parked",
              name: "spawn_agent",
              arguments: {
                agent: worker.name,
                task: "Return PARKED-REPORT-42.",
                mode: "background",
              },
            },
            {
              id: "publish-parked",
              name: "publish_value",
              arguments: { value: "approved-42" },
            },
          ],
        },
        { text: "Published approved-42 and consumed PARKED-REPORT-42." },
      ],
    )
    child_provider = fake_provider(text: "PARKED-REPORT-42", model: "gpt-5.6-luna")
    use_providers(
      "gpt-5.6-terra" => parent_provider,
      "gpt-5.6-luna" => child_provider,
    )
    agent = AimHelm::Agent.new(
      instructions: "Start the reporter and publish the reviewed value.",
      model: "gpt-5.6-terra",
      tools: [publish],
      subagents: [worker],
    )

    parent = start(prompt: "Run both requested actions.", agent:)
    perform_session(parent)
    child = parent.child_sessions.sole
    root_jobs = root_job_count

    expect(status(parent)).to eq("awaiting_approval")
    expect(status(child)).to eq("queued")

    perform_session(child)

    # The report answers the parked spawn call, but the approval still holds the turn.
    expect(status(parent)).to eq("awaiting_approval")
    expect(tool_results(parent).map { |entry| entry.payload.fetch("call_id") })
      .to eq(["spawn-parked"])
    expect(AimHelm.session(parent.id).pending_messages).to be_empty
    expect(root_job_count).to eq(root_jobs)

    approval = entries(parent).find { |entry| entry.kind == "approval_request" }
    AimHelmRails::Runtime.decide(
      session: parent,
      call_id: approval.payload.fetch("call_id"),
      verdict: :approve,
      actor: user, tenant: user.organization
    )
    perform_session(parent)

    expect(status(parent)).to eq("completed")
    expect(AimHelm.session(parent.id).pending_messages).to be_empty
    expect(tool_results(parent).map { |entry| entry.payload.fetch("call_id") })
      .to contain_exactly("spawn-parked", "publish-parked")
    expect(request_text(parent_provider.requests.second))
      .to include("PARKED-REPORT-42", "approved-42")
    expect_event_log_alignment(parent, child)
  end

  it "retries a transient provider error without writing a failed terminal" do
    provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-luna",
      turns: [
        { error: "retry this request", transient: true },
        { text: "Recovered after retry." },
      ],
    )
    use_providers("gpt-5.6-luna" => provider)
    session = start(prompt: "Recover this turn.", agent: worker_agent)

    perform_session(session)

    expect(terminals(session)).to be_empty
    expect(status(session)).to eq("queued")
    expect(root_job_count).to eq(1)

    perform_session(session)

    expect(provider.requests.count).to eq(2)
    expect(status(session)).to eq("completed")
    expect(terminals(session).count).to eq(1)
    expect_event_log_alignment(session)
  end

  it "compacts at the configured context threshold and schedules replay reminders" do
    main_provider = AimHelm::Providers::Fake.new(
      model: "gpt-5.6-luna",
      turns: [
        usage_turn("Turn 1 response", 1_000),
        usage_turn("Turn 2 response", 1_000),
        usage_turn("Turn 3 response", 1_000),
        usage_turn("Turn 4 response", 52_500),
        usage_turn("Turn 5 response", 1_000),
      ],
    )
    compactor = fake_provider(
      text: "Turns one through four established COMPACTED-CONTEXT-42.",
      usage: { input_tokens: 500, output_tokens: 50 },
      model: "claude-haiku-4-5",
    )
    use_providers(
      "gpt-5.6-luna" => main_provider,
      "claude-haiku-4-5" => compactor,
    )
    agent = AimHelm::Agent.new(
      instructions: "Maintain a long-running conversation.",
      model: "gpt-5.6-luna",
      compaction: AimHelm::Compaction.new(model: "claude-haiku-4-5", threshold: 0.05),
      reminders: [AimHelm::Reminder.new(text: "Check REMINDER-42.", every: 2, after: 1)],
    )

    session = start(prompt: "Turn 1 prompt", agent:)

    5.times do |index|
      perform_session(session)
      next if index == 4

      run(session, "Turn #{index + 2} prompt")
    end

    compactions = entries(session).select { |entry| entry.kind == "compaction" }
    expect(status(session)).to eq("completed")
    expect(terminals(session).count).to eq(5)
    expect(compactions.sole).to have_attributes(key: a_string_starting_with("compaction:"))
    expect(compactions.sole.payload.fetch("summary")).to include("COMPACTED-CONTEXT-42")
    expect(compactor.requests.count).to eq(1)

    reminders = main_provider.requests.map do |request|
      request_text(request).include?("<system-reminder>")
    end
    expect(reminders).to eq([false, true, false, true, false])
    expect(request_text(main_provider.requests.fifth))
      .to include("Earlier conversation summary", "COMPACTED-CONTEXT-42", "Turn 5 prompt")
    expect(entries(session).none? { |entry| entry.payload.to_json.include?("system-reminder") })
      .to be(true)
    expect_event_log_alignment(session)
  end

  context "with live providers", :live do
    before do
      skip "set AIM_HELM_LIVE=1 to call real providers" unless ENV["AIM_HELM_LIVE"] == "1"
    end

    it "describes the durable vision fixture as schema-valid facts" do
      result_schema = AimHelm::Schema.define do
        required(:marker).filled(:string, eql?: "RUDDER VISION 42")
        required(:shapes).array(:string, min_size?: 3)
      end
      model = live_model("AGENT_MODEL", "gpt-5.6-luna", vision: true)
      agent = AimHelm::Agent.new(
        instructions: "Inspect the supplied image and return only the required structure.",
        model:,
        output: result_schema,
      )
      prompt = [
        image_block,
        { type: "text", text: "Read the marker and name at least three visible shapes." },
      ]

      session = start(prompt:, agent:)
      perform_until_settled(session)

      expect(status(session)).to eq("completed")
      expect(result_schema.call(JSON.parse(assistant_text(session)))).to be_success
      expect_reserved_events(session, :"run.queued", :"run.started", :"run.completed")
      expect_event_log_alignment(session)
    end

    it "parks and resumes a real model's approval-gated tool call" do
      tool = AimHelmRails::Tools::Acceptance::Publish
      agent = AimHelm::Agent.new(
        instructions: "Call publish_value exactly once with value LIVE-APPROVED-42.",
        model: live_model("AGENT_MODEL", "gpt-5.6-luna"),
        reasoning: :low,
        tools: [tool],
      )
      session = start(prompt: "Publish the required value.", agent:)

      perform_until_settled(session)

      expect(status(session)).to eq("awaiting_approval")
      approval = entries(session).find { |entry| entry.kind == "approval_request" }
      AimHelmRails::Runtime.decide(
        session:,
        call_id: approval.payload.fetch("call_id"),
        verdict: :approve,
        actor: user, tenant: user.organization
      )
      perform_until_settled(session)

      expect(status(session)).to eq("completed")
      expect(tool_results(session).sole.payload.fetch("output"))
        .to eq("published LIVE-APPROVED-42")
      expect_event_log_alignment(session)
    end

    it "steers, continues, and receives two late reports from a live specialist" do
      result_schema = AimHelm::Schema.define do
        required(:marker).filled(:string, eql?: "STEERED-BETA")
        required(:finding).filled(:string)
      end
      specialist = AimHelm::Subagent.new(
        name: "marker_specialist",
        description: "Returns a requested marker and one concise finding.",
        system: "Stay within the marker task and return only the required structure.",
        model: live_model("AGENT_CHILD_MODEL", "gpt-5.6-luna"),
        reasoning: :low,
        tools: [],
        output_schema: result_schema,
      )
      agent = AimHelm::Agent.new(
        instructions: <<~TEXT,
          Spawn marker_specialist in background mode and finish without reading or waiting. When
          reports arrive in later turns, acknowledge their structured facts.
        TEXT
        model: live_model("AGENT_PARENT_MODEL", "gpt-5.6-terra"),
        reasoning: :low,
        subagents: [specialist],
      )
      parent = start(
        prompt: "Start marker_specialist with an initial ALPHA marker task.",
        agent:,
      )

      perform_until_settled(parent)

      expect(status(parent)).to eq("completed")
      child = parent.child_sessions.sole
      run(child, "Change direction and return marker STEERED-BETA.")
      perform_until_settled(child)

      first_result = result_schema.call(JSON.parse(assistant_text(child)))
      expect(first_result).to be_success
      expect(first_result.to_h.fetch(:marker)).to eq("STEERED-BETA")

      run(child, "Return STEERED-BETA again and explain the earlier finding.")
      perform_until_settled(child)

      expect(result_schema.call(JSON.parse(assistant_text(child)))).to be_success
      expect(terminals(child).count).to eq(2)
      perform_until_settled(parent)

      expect(status(parent)).to eq("completed")
      expect(terminals(parent).count).to eq(2)
      expect(entries(parent).count { |entry| entry.kind == "queued_message" }).to eq(2)
      expect_event_log_alignment(parent, child)
    end
  end

  def user
    @user ||= User.create!(organization: test_organization,
                           name: "Agent Acceptance",
                           email: "agent-acceptance-#{SecureRandom.uuid_v7}@example.com")
  end

  # Scenarios exercise definitions directly, independently of a host helmsman catalog.
  def start(prompt:, agent:)
    run(AimHelmRails::Session.create!(actor: user, tenant: user.organization), prompt, agent:)
  end

  def run(session, prompt, agent: nil)
    aim_helm_session = AimHelm.session(session.id)
    definition = agent ? registered(agent) : AimHelm.agent(session: aim_helm_session)
    definition.run(prompt, session: aim_helm_session, context: execution_context(user))
    session.reload
  end

  def registered(agent)
    agent.with(tools: AimHelmRails::Tool.identifiers(agent.tools).map do
      AimHelmRails::Tool.resolve(it)
    end)
  end

  def worker_agent
    AimHelm::Agent.new(instructions: "Answer accurately.", model: "gpt-5.6-luna")
  end

  def image_block
    fixture = AimHelmRails::Engine.root.join("spec/fixtures/aim_helm_rails/vision.png")
    {
      type: "image",
      source: {
        type: "base64",
        media_type: "image/png",
        data: Base64.strict_encode64(File.binread(fixture)),
      },
    }
  end

  def fake_provider(text:, usage: {}, model: "gpt-5.6-luna")
    AimHelm::Providers::Fake.new(model:, turns: [{ text:, usage: }])
  end

  def tool_turn(name, arguments, id:)
    { tool_calls: [{ id:, name:, arguments: }] }
  end

  def usage_turn(text, tokens)
    { text:, usage: { input_tokens: tokens, output_tokens: 0 } }
  end

  def request_text(request)
    blocks = request.fetch(:messages).flat_map(&:content)
    blocks.filter_map { |block| block["text"] }.join("\n")
  end

  def use_providers(providers)
    AimHelm.configure do |config|
      config.provider_factory = ->(model, **) { providers.fetch(model) }
    end
  end

  def live_model(variable, default, vision: false)
    id = ENV.fetch(variable, default)
    model = AimHelm.models.fetch(id)

    if vision && !model.vision
      raise AimHelm::ConfigurationError, "#{id} does not support image input"
    end

    id
  end

  def perform_session(session)
    job = enqueued_jobs.find { |candidate| candidate.fetch(:args).first == session.id.to_s }
    job_id = job.fetch("job_id")
    perform_enqueued_jobs(only: ->(candidate) { candidate.fetch("job_id") == job_id })
  end

  def perform_until_settled(session)
    AimHelmRails::AdvanceSessionJob::RETRY_ATTEMPTS.times do
      perform_session(session)
      break unless %w[queued running].include?(status(session))
    end
  end

  def entries(session) = AimHelm.session(session.id).entries

  def status(session)
    AimHelmRails::Runtime.read(session:, actor: user, tenant: user.organization).fetch(:status)
  end

  def terminals(session) = entries(session).select { |entry| entry.kind == "terminal" }
  def tool_results(session) = entries(session).select { |entry| entry.kind == "tool_result" }

  def run_records(session)
    entries(session).filter_map do |entry|
      next unless entry.kind == "run_record"

      AimHelm::Agent::Record.deserialize(entry.payload)
    end
  end

  def assistant_text(session)
    messages = AimHelm::Replay.messages(entries(session))
    messages.reverse_each.find { |message| message.role == :assistant }.text
  end

  def event_types(session)
    @events.filter_map { |session_id, event| event.type if session_id == session.id.to_s }
  end

  def root_job_count
    enqueued_jobs.count do |job|
      job.fetch(:job) == AimHelmRails::AdvanceSessionJob && job.fetch(:queue) == "agent"
    end
  end

  def session_job_count(session)
    enqueued_jobs.count do |job|
      job.fetch(:job) == AimHelmRails::AdvanceSessionJob &&
        job.fetch(:args).first == session.id.to_s
    end
  end

  def expect_reserved_events(session, *types)
    events = @events.filter_map { |session_id, event| event if session_id == session.id.to_s }
    expect(events.map(&:type)).to include(*types)
    expect(events).to all(
      have_attributes(session_id: session.id.to_s, run_id: a_string_matching(/\A[0-9a-f-]+\z/)),
    )
  end

  def expect_event_log_alignment(*sessions)
    sessions.each do |session|
      expected = terminals(session).map do |entry|
        terminal_event(entry.payload.fetch("outcome"))
      end
      actual = event_types(session).select do |type|
        %i[run.completed run.failed run.stopped].include?(type)
      end
      expect(actual).to eq(expected)
    end
  end

  def terminal_event(outcome)
    {
      "done" => :"run.completed",
      "failed" => :"run.failed",
      "stopped" => :"run.stopped",
    }.fetch(outcome)
  end
end
