# frozen_string_literal: true

require "aim_helm/features/workspace"
require "aim_helm/features/workspace/edit"
require "aim_helm/features/workspace/search"
require "aim_helm/features/workspace/tools"
require "aim_helm/features/workspace/window"

module AimHelmWorkspaceToolsSpecSupport
  class MemoryWorkspaceAdapter
    def initialize
      @documents = {}
    end

    def read(path) = @documents[path]
    def write(path, content) = @documents[path] = content
    def delete(path) = @documents.delete(path)

    def list(prefix = nil)
      paths = @documents.keys.sort
      prefix ? paths.select { it.start_with?(prefix) } : paths
    end
  end

  class AtomicMemoryWorkspaceAdapter < MemoryWorkspaceAdapter
    attr_accessor :conflict_once

    def atomic_writes? = true

    def snapshot(path)
      content = read(path)
      AimHelm::Features::Workspace::Snapshot.for(content) if content
    end

    def compare_and_write(path, content, expected_revision:)
      inject_conflict(path) if conflict_once

      current = snapshot(path)

      unless current&.revision == expected_revision
        raise AimHelm::Features::Workspace::ConflictError,
              path
      end

      write(path, content)
      snapshot(path)
    end

    private

    def inject_conflict(path)
      self.conflict_once = false
      write(path, "#{read(path)}Human note\n")
      raise AimHelm::Features::Workspace::ConflictError, path
    end
  end
end

RSpec.describe AimHelm::Features::Workspace::Tools do
  let(:app) { Object.new }
  let(:context) { Data.define(:app).new(app:) }

  let(:adapters) do
    Hash.new do |store, key|
      store[key] = AimHelmWorkspaceToolsSpecSupport::AtomicMemoryWorkspaceAdapter.new
    end
  end

  let(:workspace) do
    AimHelm::Features::Workspace.adapter { |tool_context| adapters[tool_context.app] }
  end

  let(:tools) do
    workspace.tools(name: :memory, purpose: "private durable memory")
             .to_h { [it.name, it] }
  end

  it "builds stable names and identifiers" do
    definitions = tools.values

    expect(definitions.map(&:name)).to eq(
      %w[memory_list memory_read memory_write memory_edit memory_search],
    )
    expect(definitions.map(&:identifier)).to eq(
      %w[workspace/memory/list workspace/memory/read workspace/memory/write
         workspace/memory/edit workspace/memory/search],
    )
    expect(definitions.map(&:description)).to all(include("private durable memory"))
  end

  it "resolves the adapter from trusted tool context" do
    other = Data.define(:app).new(app: Object.new)

    write("profile.md", "Concise answers", context:)

    expect(read("profile.md", context:).content).to eq("1: Concise answers")
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

    expect(listed.content).to eq("notes/one.md")
    expect(window.content).to eq("2: two\n\n[showing lines 2-2 of 3]")
  end

  it "edits a legacy four-method adapter" do
    legacy = AimHelmWorkspaceToolsSpecSupport::MemoryWorkspaceAdapter.new
    binding = AimHelm::Features::Workspace.adapter { legacy }
    edit = binding.tools(name: :memory, purpose: "memory", only: [:edit]).fetch(0)
    legacy.write("profile.md", "Prefers long answers")

    result = edit.call(
      { "path" => "profile.md", "old_string" => "long", "new_string" => "short" },
      context:,
    )

    expect(result).to be_success
    expect(legacy.read("profile.md")).to eq("Prefers short answers")
  end

  it "searches paths with independent before and after context" do
    write("pages/one.html", "header\n<section>\nneedle\n</section>\nfooter\n", context:)
    write("pages/two.html", "ignore\nneedle two\nafter\n", context:)
    write("notes/one.md", "needle elsewhere\n", context:)

    result = tools.fetch("memory_search").call(
      { "query" => "needle", "prefix" => "pages/", "before" => 1, "after" => 2 },
      context:,
    )

    expect(result.content).to eq(<<~RESULT.chomp)
      pages/one.html-2-<section>
      pages/one.html:3:needle
      pages/one.html-4-</section>
      pages/one.html-5-footer
      --
      pages/two.html-1-ignore
      pages/two.html:2:needle two
      pages/two.html-3-after
    RESULT
  end

  it "centers a minified HTML line around the match" do
    html = "#{"a" * 3_000}<main>needle</main>#{"z" * 3_000}"
    write("page.html", html, context:)

    result = tools.fetch("memory_search").call(
      { "query" => "needle", "path" => "page.html", "before" => 0, "after" => 0 },
      context:,
    )

    expect(result.content.length).to be < 2_100
    expect(result.content).to start_with("page.html:1:…")
    expect(result.content).to include("<main>needle</main>")
    expect(result.content).to end_with("…")
  end

  it "rejects ambiguous path and prefix scopes" do
    result = tools.fetch("memory_search").call(
      { "query" => "needle", "path" => "page.html", "prefix" => "pages/" },
      context:,
    )

    expect(result).to be_failure
    expect(result.content).to include("pass path or prefix, not both")
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
