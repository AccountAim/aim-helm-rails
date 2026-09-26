RSpec.describe AimHelmRails::Features::Workspace::Shell do
  let(:tenant) { test_organization }
  let(:scratch) { MemoryStore.new(kind: :scratch, tenant:, root: "chat-1/") }
  let(:knowledge_base) { MemoryStore.new(kind: :knowledge_base, tenant:) }
  let(:stores) { { "scratch" => scratch, "knowledge_base" => knowledge_base } }

  def run(script, paths: []) = described_class.call(stores, script, paths:).to_h

  it "keeps writes under scratch and nothing else" do
    report = run("echo hello > scratch/notes.txt; echo lost > /tmp/x.txt")

    expect(report.fetch(:written)).to eq(["scratch/notes.txt"])
    expect(scratch.read("notes.txt")).to eq("hello\n")
    again = run("cat scratch/notes.txt", paths: ["scratch/notes.txt"])
    expect(again.fetch(:stdout)).to eq("hello\n")
  end

  it "mounts other stores read-only beside scratch" do
    knowledge_base.write("app.md", "# App\nCount at the distinct_id grain.\n")

    report = run(
      "rg -n grain knowledge_base/app.md > scratch/hits.txt; " \
      "echo tampered >> knowledge_base/app.md; cat scratch/hits.txt",
      paths: ["knowledge_base/app.md"],
    )

    expect(report.fetch(:stdout)).to eq("2:Count at the distinct_id grain.\n")
    expect(report.fetch(:written)).to eq(["scratch/hits.txt"])
    expect(report.fetch(:discarded)).to eq(["knowledge_base/app.md"])
    expect(knowledge_base.read("app.md")).to eq("# App\nCount at the distinct_id grain.\n")
  end

  it "carries big command output through pipes but cuts what the agent gets back" do
    stub_const("AimHelmRails::Features::Workspace::Shell::OUTPUT_LIMIT", 100)
    report = run("seq 1 100000 | rg -o '9' | wc -l; seq 1 100000")

    expect(report.fetch(:stdout)).to start_with("50000\n1\n2\n")
    expect(report.fetch(:stdout)).to end_with(described_class::CUT)
  end

  it "lists what the sandbox can run after a missing command" do
    report = run("python3 -c 'print(1)'")

    expect(report.fetch(:exit_code)).to eq(127)
    expect(report.fetch(:available_commands)).to include("rg", "awk")
  end
end
