require "rails_helper"

RSpec.describe Artifact, "state machine" do
  let(:campaign) { create(:campaign) }
  let(:user) { create(:user) }

  it "chỉ cho phép transition hợp lệ: draft → in_review → approved" do
    a = create(:artifact, campaign: campaign)
    expect(a.can_transition_to?("in_review")).to be true
    a.update!(approval_status: "in_review")
    a.update!(approval_status: "approved")
    expect(a.reload.approval_status).to eq("approved")
  end

  it "cấm nhảy cóc draft → approved" do
    a = create(:artifact, campaign: campaign)
    a.approval_status = "approved"
    expect(a).not_to be_valid
    expect(a.errors[:approval_status]).to be_present
  end

  it "chỉnh sửa sau khi approved đưa về draft thành version mới — version approved vẫn nằm trong history" do
    a = create(:artifact, campaign: campaign)
    a.update!(approval_status: "in_review")
    a.update!(approval_status: "approved")
    a.new_version!("nội dung mới", ai_generated: false, user: user)
    a.reload
    expect(a.version).to eq(2)
    expect(a.approval_status).to eq("draft")
    expect(a.artifact_versions.find_by(version: 1).body).to eq("Nội dung brief") # bản đã duyệt không mất
  end

  it "withdraw! chỉ hoạt động với in_review và hủy round đang mở" do
    a = create(:artifact, campaign: campaign)
    a.update!(approval_status: "in_review")
    round = a.approval_rounds.create!(artifact_version: a.version, status: "pending")
    a.withdraw!
    expect(a.reload.approval_status).to eq("draft")
    expect(round.reload.status).to eq("cancelled")
  end

  it "restore_version! tạo version mới, không đụng history" do
    a = create(:artifact, campaign: campaign)
    a.new_version!("v2 content", ai_generated: false, user: user)
    expect(a.version).to eq(2)
    a.restore_version!(1, user: user)
    a.reload
    expect(a.version).to eq(3)
    expect(a.body).to eq("Nội dung brief")
    expect(a.artifact_versions.count).to eq(3)
  end

  it "duplicate! tạo bản sao riêng trong cùng campaign" do
    a = create(:artifact, campaign: campaign, channel: "Facebook")
    copy = a.duplicate!(user: user)
    expect(copy.id).not_to eq(a.id)
    expect(copy.channel).to eq("Facebook")
    expect(copy.ai_metadata["duplicated_from_id"]).to eq(a.id)
  end
end
