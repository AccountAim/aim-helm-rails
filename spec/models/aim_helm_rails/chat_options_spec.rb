RSpec.describe AimHelmRails::ChatOptions do
  it "parses a key into its helmsman, model, and reasoning" do
    expect(described_class.new("probe:gpt-5.6-sol/high"))
      .to have_attributes(helmsman: "probe", model: "gpt-5.6-sol", reasoning: :high)
    expect(described_class.new("subagents/scout"))
      .to have_attributes(helmsman: "subagents/scout", model: nil, reasoning: nil)
    expect { described_class.new("probe:low") }.to raise_error(ArgumentError)
  end

  it "builds the helmsman's agent, overridden by the key's model and reasoning" do
    declared = AimHelm.agent("gpt-5.6-luna", reasoning: :low)
    allow(AimHelmRails.host).to receive(:helmsman).with("probe").and_return(double(agent: declared))

    expect(described_class.new("probe").agent).to eq(declared)
    expect(described_class.new("probe:gpt-5.6-sol/high").agent)
      .to have_attributes(model: "gpt-5.6-sol", reasoning: :high)
  end
end
