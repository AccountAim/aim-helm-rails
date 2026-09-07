RSpec.describe AimHelmRails::ClippedJson do
  it "passes short text and every budgetless level through untouched" do
    text = "a" * 600

    expect(described_class.call("short", detail: :brief)).to eq("short")
    expect(described_class.call(text, detail: :raw)).to eq(text)
    expect(described_class.call(nil, detail: :full)).to be_nil
  end

  it "clips to the level's byte budget and says what was shown" do
    clipped = described_class.call("é" * 400, detail: :brief)

    expect(clipped.bytesize).to be < 800
    expect(clipped).to end_with("… [truncated: showing 500 of 800 bytes]")
    expect(clipped).to be_valid_encoding
  end

  it "appends the hint that says how to reach the rest" do
    expect(described_class.call("x" * 501, detail: :brief, hint: "explore it with exec_cli"))
      .to end_with("[truncated: showing 500 of 501 bytes; explore it with exec_cli]")
  end
end
