RSpec.describe AimHelmRails::Helmsman do
  it "is named by its class path" do
    expect(Class.new(described_class) { def self.name = "Subagents::KnowledgeBase" }.helmsman_name)
      .to eq("subagents/knowledge_base")
  end
end
