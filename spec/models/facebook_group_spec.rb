require "rails_helper"

RSpec.describe FacebookGroup do
  let(:org) { create(:organization) }

  it "chuẩn hoá link nhóm: bỏ query, m./web., thiếu https" do
    {
      "https://www.facebook.com/groups/muabancanho?ref=share&mibextid=abc" => "https://www.facebook.com/groups/muabancanho",
      "m.facebook.com/groups/123456789/" => "https://www.facebook.com/groups/123456789",
      "https://web.facebook.com/groups/nhom.bds/permalink/999" => "https://www.facebook.com/groups/nhom.bds"
    }.each do |input, expected|
      group = described_class.create!(organization: org, name: "N", url: input)
      expect(group.url).to eq(expected)
      group.destroy!
    end
  end

  it "từ chối link không phải nhóm Facebook" do
    [ "https://www.facebook.com/KaoriRealEstate", "https://example.com/groups/abc", "facebook.com/groups/" ].each do |bad|
      group = described_class.new(organization: org, name: "N", url: bad)
      expect(group).not_to be_valid, bad
      expect(group.errors[:url]).to be_present
    end
  end

  it "một link nhóm chỉ có một lần trong mỗi workspace (so sánh sau chuẩn hoá)" do
    described_class.create!(organization: org, name: "A", url: "https://www.facebook.com/groups/abc")
    dup = described_class.new(organization: org, name: "B", url: "https://m.facebook.com/groups/abc?ref=x")
    expect(dup).not_to be_valid
    other_org = described_class.new(organization: create(:organization), name: "B", url: "https://www.facebook.com/groups/abc")
    expect(other_org).to be_valid
  end

  it "chuẩn hoá nhãn và liệt kê nhãn của workspace" do
    group = described_class.create!(organization: org, name: "N", url: "https://www.facebook.com/groups/x", tags: " Cầu Giấy ,căn hộ,, Cầu Giấy ")
    expect(group.tags).to eq("Cầu Giấy, căn hộ")
    expect(described_class.all_tags(org)).to eq([ "Cầu Giấy", "căn hộ" ])
  end

  it "người phụ trách mặc định phải là thành viên nội bộ" do
    staff = create(:user)
    client = create(:user)
    create(:membership, organization: org, user: staff, role: "copywriter")
    create(:membership, organization: org, user: client, role: "client")
    expect(build(:facebook_group, organization: org, default_assignee: staff)).to be_valid
    expect(build(:facebook_group, organization: org, default_assignee: client)).not_to be_valid
    expect(build(:facebook_group, organization: org, default_assignee: create(:user))).not_to be_valid
  end

  it "không xoá cứng nhóm đã có lượt chia sẻ" do
    owner = create(:user)
    create(:membership, organization: org, user: owner, role: "owner")
    post = create(:facebook_post, :published, organization: org)
    group = create(:facebook_group, organization: org)
    FacebookGroupShare.create!(organization: org, facebook_post: post, facebook_group: group, assignee: owner, scheduled_at: 1.hour.from_now)
    expect(group.destroy).to be false
    expect(group.errors).to be_present
  end
end
