RSpec.describe AimHelmRails::ChatKey do
  it "reads the helmsman, model, and reasoning from a key" do
    expect(described_class.new("probe:gpt-6-sol/high"))
      .to have_attributes(helmsman: "probe", model: "gpt-6-sol", reasoning: :high)
  end

  it "reads a bare key as the helmsman alone, slashes included" do
    expect(described_class.new("subagents/scout"))
      .to have_attributes(helmsman: "subagents/scout", model: nil, reasoning: nil)
  end

  it "rejects a key that is not helmsman:model/reasoning" do
    expect { described_class.new("probe:low") }.to raise_error(ArgumentError)
  end

  it "builds the helmsman's agent, overridden by the key's model and reasoning" do
    declared = AimHelm.agent("gpt-6-luna", reasoning: :low)
    allow(AimHelmRails.host).to receive(:helmsman).with("probe").and_return(double(agent: declared))

    expect(described_class.new("probe").agent).to eq(declared)
    expect(described_class.new("probe:gpt-6-sol/high").agent)
      .to have_attributes(model: "gpt-6-sol", reasoning: :high)
  end
end
