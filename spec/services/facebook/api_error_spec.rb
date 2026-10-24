require "rails_helper"

RSpec.describe Facebook::ApiError do
  it "phân loại lỗi Meta theo code" do
    expect(described_class.new("x", code: 190).kind).to eq(:token_expired)
    expect(described_class.new("x", code: 102).kind).to eq(:token_expired)
    expect(described_class.new("x", code: 10).kind).to eq(:permission)
    expect(described_class.new("x", code: 200).kind).to eq(:permission)
    expect(described_class.new("x", code: 4).kind).to eq(:rate_limited)
    expect(described_class.new("x", code: 32).kind).to eq(:rate_limited)
    expect(described_class.new("x", code: 1).kind).to eq(:transient)
    expect(described_class.new("x", http_status: 503).kind).to eq(:transient)
    expect(described_class.new("x", code: 368).kind).to eq(:policy)
    expect(described_class.new("Invalid parameter", code: 100).kind).to eq(:validation)
    expect(described_class.new("x", code: 999).kind).to eq(:permanent)
  end

  it "chỉ rate limit / transient mới retry" do
    expect(described_class.new("x", code: 4)).to be_transient
    expect(described_class.new("x", code: 190)).not_to be_transient
    expect(described_class.new("x", code: 10)).not_to be_transient
    expect(described_class.new("x", code: 100)).not_to be_transient
  end

  it "không để token lọt vào message" do
    e = described_class.new("bad access_token=EAAABBBCCCDDDEEEFFFGGGHHHIIIJJJ", code: 190)
    expect(e.message).not_to include("EAAABBB")
  end
end
