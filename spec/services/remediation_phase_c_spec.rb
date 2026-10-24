require "rails_helper"

# PHASE C — approval version integrity (regression chính của audit).
RSpec.describe "Remediation Phase C: approval version integrity" do
  let(:org) { create(:organization) }
  let(:editor) { create(:user) }
  let(:reviewer) { create(:user) }
  before do
    create(:membership, organization: org, user: editor, role: "copywriter")
    create(:membership, organization: org, user: reviewer, role: "approver")
  end
  let(:campaign) { create(:campaign, organization: org) }
  let(:artifact) { create(:artifact, campaign: campaign) }

  it "edit tạo v2 → round v1 bị hủy → quyết định v1 bị từ chối, v2 còn draft" do
    round = Approvals::Submit.call(artifact: artifact, user: editor, reviewers: [reviewer])
    expect(artifact.reload.approval_status).to eq("in_review")

    # Editor sửa khi đang chờ duyệt → v2 draft + round v1 auto-cancel.
    artifact.new_version!("nội dung v2 hoàn toàn mới", ai_generated: false, user: editor)

    expect(artifact.reload.version).to eq(2)
    expect(artifact.reload.approval_status).to eq("draft")
    expect(round.reload.status).to eq("cancelled")

    expect {
      Approvals::Decide.call(round: round.reload, user: reviewer, decision: "approved")
    }.to raise_error(ArgumentError)
    expect(artifact.reload.approval_status).to eq("draft") # KHÔNG bị approved
  end

  it "decide trên round của version cũ bị từ chối dù round còn pending" do
    round = Approvals::Submit.call(artifact: artifact, user: editor, reviewers: [reviewer])
    # Giả lập round không bị cancel nhưng version artifact đã đổi (defense in depth).
    artifact.update_column(:version, 99)
    expect {
      Approvals::Decide.call(round: round, user: reviewer, decision: "approved")
    }.to raise_error(ArgumentError, /version cũ/)
    artifact.update_column(:version, 1)
  end

  it "không submit/decide round đã cancelled" do
    round = Approvals::Submit.call(artifact: artifact, user: editor, reviewers: [reviewer])
    round.update!(status: "cancelled")
    expect {
      Approvals::Decide.call(round: round, user: reviewer, decision: "approved")
    }.to raise_error(ArgumentError, /đã kết thúc/)
  end

  it "approve v1 hợp lệ; edit sau đó tạo v2 DRAFT — approval không dính v2" do
    round = Approvals::Submit.call(artifact: artifact, user: editor, reviewers: [reviewer])
    Approvals::Decide.call(round: round, user: reviewer, decision: "approved")
    expect(artifact.reload.approval_status).to eq("approved")

    artifact.new_version!("nội dung mới sau duyệt", ai_generated: false, user: editor)
    expect(artifact.reload.version).to eq(2)
    expect(artifact.reload.approval_status).to eq("draft")
    # Version 1 đã duyệt vẫn nguyên vẹn trong history.
    expect(artifact.artifact_versions.find_by(version: 1).body).to eq("Nội dung brief")
  end

  it "changes_requested/rejected không ghi đè lên version mới hơn" do
    round = Approvals::Submit.call(artifact: artifact, user: editor, reviewers: [reviewer])
    artifact.new_version!("v2", ai_generated: false, user: editor) # hủy round v1
    round.update_column(:status, "pending") # ép round sống lại để test sync guard

    round.approval_decisions.create!(user: reviewer, decision: "changes_requested")
    round.update_column(:status, "changes_requested")
    round.sync_artifact_status

    expect(artifact.reload.approval_status).to eq("draft") # v2 không bị đánh dấu
  end
end
