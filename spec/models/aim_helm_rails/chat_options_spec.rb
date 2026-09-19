RSpec.describe AimHelmRails::ChatOptions do
  let(:offered) do
    [{ key: "probe:gpt-5.6-terra/low", label: "Quick" },
     { key: "probe:gpt-5.6-sol/high", label: "Deep" },
     { key: "scout", label: "Scout" }]
  end

  before do
    allow(AimHelmRails.host).to receive(:chat_options).and_return(offered)
  end

  it "parses a key into its helmsman, model, and reasoning" do
    expect(described_class.new(key: "probe:gpt-5.6-sol/high"))
      .to have_attributes(helmsman: "probe", model: "gpt-5.6-sol", reasoning: :high)
    expect(described_class.new(key: "subagents/scout"))
      .to have_attributes(helmsman: "subagents/scout", model: nil, reasoning: nil)
  end

  it "rejects a malformed key and an unknown model" do
    expect { described_class.new(key: "probe:low") }.to raise_error(AimHelm::ConfigurationError)
    expect { described_class.new(key: "probe:gpt-9/low") }.to raise_error(KeyError)
  end

  it "builds the helmsman's agent, overridden by the key's model and reasoning" do
    declared = AimHelm.agent("gpt-5.6-luna", reasoning: :low)
    allow(AimHelmRails.host).to receive(:helmsman).with("probe").and_return(double(agent: declared))

    expect(described_class.new(key: "probe").agent).to eq(declared)
    expect(described_class.new(key: "probe:gpt-5.6-sol/high").agent)
      .to have_attributes(model: "gpt-5.6-sol", reasoning: :high)
  end

  it "carries the host's selection to the composer" do
    expect(described_class.new(key: "probe", label: "Probe", selected: true).as_json)
      .to eq(key: "probe", label: "Probe", selected: true)
  end

  it "offers an unsaved chat every choice, and pins one opened on a key" do
    expect(described_class.for(AimHelmRails::Session.new).map(&:label)).to eq(%w[Quick Deep Scout])
    expect(described_class.for(AimHelmRails::Session.new(helmsman: "scout")).map(&:label))
      .to eq(["Scout"])
    expect(described_class.for(AimHelmRails::Session.new(helmsman: "probe")).map(&:label))
      .to eq(["probe"])
  end
end
