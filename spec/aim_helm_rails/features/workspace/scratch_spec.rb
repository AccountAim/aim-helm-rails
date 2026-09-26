RSpec.describe AimHelmRails::Features::Workspace::Bash do
  let(:user) do
    User.create!(organization: test_organization, name: "Scratch",
                 email: "scratch-#{SecureRandom.uuid_v7}@example.com")
  end

  let(:chat) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }

  let(:subagent_chat) do
    AimHelmRails::Session.create!(actor: user, tenant: user.organization, parent_session: chat)
  end

  let(:other_chat) { AimHelmRails::Session.create!(actor: user, tenant: user.organization) }
  let(:shell) { AimHelmRails::Features::Workspace::Integration.workspace_bash }

  def context_for(session)
    AimHelm::Tools::Context.new(
      session: AimHelm.session(session.id),
      events: AimHelm::Tools::Broadcaster.new(sink: ->(_) {}, call_id: "call-1"),
      app: execution_context(user),
      call_id: "call-1",
      run_id: "run-1",
      turn_id: "turn-1",
    )
  end

  def run(session, script, paths: [])
    result = shell.call({ "script" => script, "paths" => paths }, context: context_for(session))
    JSON.parse(result.content)
  end

  it "keeps scratch across a chat and its subagents, apart from other chats" do
    expect(run(chat, "echo hello > scratch/notes.txt").fetch("written"))
      .to eq(["scratch/notes.txt"])
    shared = run(subagent_chat, "cat scratch/notes.txt", paths: ["scratch/notes.txt"])
    expect(shared.fetch("stdout")).to eq("hello\n")
    expect(run(chat, "ls scratch").fetch("stdout")).to eq("")
    expect(run(other_chat, "cat scratch/notes.txt", paths: ["scratch/notes.txt"]).fetch("stderr"))
      .to include("file not found")
  end

  it "mounts other stores read-only beside scratch" do
    knowledge_base = AimHelmRails::Features::Workspace::Integration.knowledge_base_store(context_for(chat))
    knowledge_base.write("app.md", "# App\nCount at the distinct_id grain.\n")

    result = run(
      chat,
      "rg -n grain knowledge_base/app.md > scratch/hits.txt; " \
      "echo tampered >> knowledge_base/app.md; cat scratch/hits.txt",
      paths: ["knowledge_base/app.md"],
    )

    expect(result.fetch("stdout")).to eq("2:Count at the distinct_id grain.\n")
    expect(result.fetch("written")).to eq(["scratch/hits.txt"])
    expect(result.fetch("discarded")).to eq(["knowledge_base/app.md"])
    expect(knowledge_base.read("app.md")).to eq("# App\nCount at the distinct_id grain.\n")
  end

  it "saves the files a cut listing still names and says the rest were not saved" do
    stub_const("AimHelmRails::Features::Workspace::Shell::SANDBOX_OUTPUT", 40)
    result = run(chat, "for n in 1 2 3 4 5 6; do echo $n > scratch/file-$n.txt; done")

    expect(result.fetch("written")).to eq(["scratch/file-1.txt", "scratch/file-2.txt"])
    expect(result.fetch("warning")).to include("listing was cut")
  end

  it "carries big command output through pipes but cuts what the agent gets back" do
    stub_const("AimHelmRails::Features::Workspace::Shell::OUTPUT_LIMIT", 100)
    result = run(chat, "seq 1 100000 | rg -o '9' | wc -l; seq 1 100000")

    expect(result.fetch("stdout")).to start_with("50000\n1\n2\n")
    expect(result.fetch("stdout")).to end_with(AimHelmRails::Features::Workspace::Shell::CUT)
    expect(result.fetch("stdout").bytesize).to be < 300
  end

  it "refuses a path outside the known mounts" do
    result = shell.call({ "script" => "ls", "paths" => ["etc/passwd"] }, context: context_for(chat))

    expect(result).to be_failure
    expect(result.content).to include("unknown mount")
  end
end
