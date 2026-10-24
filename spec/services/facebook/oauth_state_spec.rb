require "rails_helper"

RSpec.describe Facebook::OauthState do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:nonce) { described_class.new_nonce }

  it "chấp nhận state hợp lệ đúng user/org/nonce và trả payload" do
    token = described_class.generate(user: user, org: org, nonce: nonce, page_hint: "https://facebook.com/abc", mode: "live")
    payload = described_class.verify!(token, user: user, org: org, nonce: nonce)
    expect(payload["page_hint"]).to eq("https://facebook.com/abc")
    expect(payload["mode"]).to eq("live")
  end

  it "từ chối state bị sửa/chữ ký sai" do
    token = described_class.generate(user: user, org: org, nonce: nonce)
    expect { described_class.verify!(token + "x", user: user, org: org, nonce: nonce) }.to raise_error(described_class::Invalid)
    expect { described_class.verify!("", user: user, org: org, nonce: nonce) }.to raise_error(described_class::Invalid)
  end

  it "từ chối state của user khác (CSRF/login-swap)" do
    token = described_class.generate(user: user, org: org, nonce: nonce)
    expect { described_class.verify!(token, user: other_user, org: org, nonce: nonce) }.to raise_error(described_class::Invalid)
  end

  it "từ chối khi nonce trong session không khớp hoặc thiếu" do
    token = described_class.generate(user: user, org: org, nonce: nonce)
    expect { described_class.verify!(token, user: user, org: org, nonce: "khac") }.to raise_error(described_class::Invalid)
    expect { described_class.verify!(token, user: user, org: org, nonce: nil) }.to raise_error(described_class::Invalid)
  end

  it "hết hạn sau 10 phút" do
    token = described_class.generate(user: user, org: org, nonce: nonce)
    travel_to 11.minutes.from_now do
      expect { described_class.verify!(token, user: user, org: org, nonce: nonce) }.to raise_error(described_class::Invalid)
    end
  end
end
