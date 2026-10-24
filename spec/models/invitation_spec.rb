require "rails_helper"

RSpec.describe Invitation do
  let(:org) { create(:organization) }

  it "token tự sinh, hết hạn sau 7 ngày" do
    i = described_class.create!(organization: org, email: "a@b.vn", role: "client")
    expect(i.token).to be_present
    expect(i.expires_at).to be > 6.days.from_now
    expect(i).to be_usable
  end

  it "revoked/expired/accepted thì không dùng được" do
    i = described_class.create!(organization: org, email: "a@b.vn", role: "client")
    i.update!(revoked_at: Time.current)
    expect(i).not_to be_usable

    j = described_class.create!(organization: org, email: "c@d.vn", role: "client")
    j.update!(expires_at: 1.minute.ago)
    expect(j).not_to be_usable
  end
end
