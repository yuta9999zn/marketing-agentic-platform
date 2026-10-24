require "rails_helper"

RSpec.describe Facebook::PageUrlParser do
  {
    "https://www.facebook.com/marketflow.demo" => { username: "marketflow.demo" },
    "facebook.com/marketflow.demo/" => { username: "marketflow.demo" },
    "https://m.facebook.com/marketflow.demo?mibextid=abc" => { username: "marketflow.demo" },
    "https://www.facebook.com/profile.php?id=100000000000001" => { id: "100000000000001" },
    "https://www.facebook.com/pages/Ten-Page/100000000000001" => { id: "100000000000001" },
    "https://www.facebook.com/Ten-Page-100000000000001" => { username: "Ten-Page" },
    "100000000000001" => { id: "100000000000001" },
    "@marketflow.demo" => { username: "marketflow.demo" },
    "https://fb.com/marketflow.demo" => { username: "marketflow.demo" }
  }.each do |input, expected|
    it "parse #{input}" do
      res = described_class.call(input)
      expect(res.id).to eq(expected[:id])
      expect(res.username).to eq(expected[:username])
    end
  end

  it "không nhận link không phải facebook" do
    expect(described_class.call("https://example.com/page").present?).to be false
  end

  it "khớp Page theo id, username hoặc slug trong link" do
    page = { "id" => "100000000000001", "username" => "marketflow.demo", "link" => "https://www.facebook.com/marketflow.demo" }
    expect(described_class.match?(page, "https://www.facebook.com/MarketFlow.Demo")).to be true
    expect(described_class.match?(page, "100000000000001")).to be true
    expect(described_class.match?(page, "https://www.facebook.com/other")).to be false
  end
end
