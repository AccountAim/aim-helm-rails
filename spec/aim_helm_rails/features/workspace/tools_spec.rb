module WorkspaceToolsSpecSupport
  class MemoryWorkspaceAdapter
    def initialize
      @documents = {}
    end

    def read(path) = @documents[path]
    def write(path, content) = @documents[path] = content
    def delete(path) = @documents.delete(path)

    def list(prefix = nil, text: nil)
      paths = @documents.keys.sort
      paths = paths.select { it.start_with?(prefix) } if prefix
      text ? paths.select { it.include?(text) || @documents[it].include?(text) } : paths
    end

    def entries(prefix = nil, text: nil)
      list(prefix, text:).map { [it, @documents[it].bytesize, @documents[it].count("\n")] }
    end
  end

  class AtomicMemoryWorkspaceAdapter < MemoryWorkspaceAdapter
    attr_accessor :conflict_once

    def atomic_writes? = true

    def snapshot(path)
      content = read(path)
      AimHelmRails::Features::Workspace::Snapshot.for(content) if content
    end

    def compare_and_write(path, content, expected_revision:)
      inject_conflict(path) if conflict_once

      current = snapshot(path)

      unless current&.revision == expected_revision
        raise AimHelmRails::Features::Workspace::ConflictError,
              path
      end

      write(path, content)
      snapshot(path)
    end

    private

    def inject_conflict(path)
      self.conflict_once = false
      write(path, "#{read(path)}Human note\n")
      raise AimHelmRails::Features::Workspace::ConflictError, path
    end
  end
end

RSpec.describe AimHelmRails::Features::Workspace::Tools do
  let(:app) { Object.new }
  let(:context) { Data.define(:app).new(app:) }

  let(:adapters) do
    Hash.new do |store, key|
      store[key] = WorkspaceToolsSpecSupport::AtomicMemoryWorkspaceAdapter.new
    end
  end

  let(:workspace) do
    AimHelmRails::Features::Workspace.adapter { |tool_context| adapters[tool_context.app] }
  end

  let(:tools) do
    workspace.tools(name: :memory, purpose: "private durable memory")
             .to_h { [it.name, it] }
  end

  it "resolves the adapter from trusted tool context" do
    other = Data.define(:app).new(app: Object.new)

    write("profile.md", "Concise answers", context:)

    expect(read("memory/profile.md", context:).content).to eq("1: Concise answers")
    expect(read("profile.md", context: other)).to be_failure
  end

  it "lists paths and reads bounded line windows" do
    write("notes/one.md", "one\ntwo\nthree\n", context:)
    write("profile.md", "profile", context:)

    listed = tools.fetch("memory_list").call({ "prefix" => "notes/" }, context:)
    window = tools.fetch("memory_read").call(
      { "path" => "notes/one.md", "offset" => 2, "limit" => 1 },
      context:,
    )

    expect(listed.content).to eq("memory/notes/one.md  3 lines, 14 Bytes")
    expect(window.content).to eq(<<~WINDOW.chomp)
      2: two

      [lines 2-2 of 3; the rest through workspace_bash with paths ["memory/notes/one.md"],
      e.g. sed -n '3,62p' memory/notes/one.md or rg -n -C 2 PATTERN memory/notes/one.md]
    WINDOW
  end

  it "says how long a file is when the window starts past its end" do
    write("notes/one.md", "one\ntwo\nthree\n", context:)

    window = tools.fetch("memory_read").call({ "path" => "notes/one.md", "offset" => 10 }, context:)

    expect(window.content).to eq("[only 3 lines; start at or before line 3]")
  end

  it "edits a legacy four-method adapter" do
    legacy = WorkspaceToolsSpecSupport::MemoryWorkspaceAdapter.new
    binding = AimHelmRails::Features::Workspace.adapter { legacy }
    edit = binding.tools(name: :memory, purpose: "memory", only: [:edit]).fetch(0)
    legacy.write("profile.md", "Prefers long answers")

    result = edit.call(
      { "path" => "profile.md", "old_string" => "long", "new_string" => "short" },
      context:,
    )

    expect(result).to be_success
    expect(legacy.read("profile.md")).to eq("Prefers short answers")
  end

  it "lists only the paths mentioning a text" do
    write("pages/one.html", "header\nneedle\n", context:)
    write("pages/two.html", "ignore\n", context:)
    write("notes/needle.md", "elsewhere\n", context:)

    listed = tools.fetch("memory_list").call({ "text" => "needle" }, context:)

    expect(listed.content)
      .to eq("memory/notes/needle.md  1 lines, 10 Bytes\nmemory/pages/one.html  2 lines, 14 Bytes")
  end

  it "cuts a single line that is over the byte budget on its own" do
    write("query.sql", "SELECT #{"x" * 150_000} FROM t", context:)

    result = read("memory/query.sql", context:)

    expect(result.content.bytesize).to be < 5_000
    expect(result.content).to include("…", "[line 1 cut at 4000 bytes, 1 lines in all")
  end

  it "refuses paths that are not relative document paths" do
    %w[../up.md /abs.md ./here.md a//b.md].each do |path|
      result = tools.fetch("memory_write").call({ "path" => path, "content" => "x" }, context:)

      expect(result).to be_failure
      expect(result.content).to include("not a document path")
    end
  end

  it "refuses a path over the stored length" do
    path = "#{"a" * 512}.md"
    result = tools.fetch("memory_write").call({ "path" => path, "content" => "x" }, context:)

    expect(result).to be_failure
    expect(result.content).to include("path over 512 characters")
  end

  it "reapplies an atomic edit after an unrelated conflict" do
    adapter = adapters[app]
    adapter.write("profile.md", "Style: long\n")
    adapter.conflict_once = true

    result = tools.fetch("memory_edit").call(
      { "path" => "profile.md", "old_string" => "long", "new_string" => "short" },
      context:,
    )

    expect(result).to be_success
    expect(adapter.read("profile.md")).to eq("Style: short\nHuman note\n")
  end

  it "refuses an ambiguous edit" do
    write("profile.md", "brief, brief", context:)

    result = tools.fetch("memory_edit").call(
      { "path" => "profile.md", "old_string" => "brief", "new_string" => "short" },
      context:,
    )

    expect(result).to be_failure
    expect(result.content).to include("matched 2 places")
    expect(adapters.fetch(app).read("profile.md")).to eq("brief, brief")
  end

  private

  def write(path, content, context:)
    tools.fetch("memory_write").call({ "path" => path, "content" => content }, context:)
  end

  def read(path, context:)
    tools.fetch("memory_read").call({ "path" => path }, context:)
  end
end
