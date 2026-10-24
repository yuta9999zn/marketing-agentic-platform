require "rails_helper"

RSpec.describe "Approval rounds" do
  let(:org) { create(:organization) }
  let(:editor) { create(:user) }
  let(:reviewer_a) { create(:user) }
  let(:reviewer_b) { create(:user) }
  let(:outsider) { create(:user) }

  before do
    create(:membership, organization: org, user: editor, role: "copywriter")
    create(:membership, organization: org, user: reviewer_a, role: "approver")
    create(:membership, organization: org, user: reviewer_b, role: "manager")
  end

  let(:campaign) { create(:campaign, organization: org) }
  let(:artifact) { create(:artifact, campaign: campaign) }

  def submit!(reviewers)
    Approvals::Submit.call(artifact: artifact.reload, user: editor, reviewers: reviewers, quorum: nil)
  end

  it "submit mở round pending, artifact sang in_review, reviewer nhận notification" do
    round = submit!([reviewer_a])
    expect(round.status).to eq("pending")
    expect(round.reviewer_ids).to eq([reviewer_a.id])
    expect(artifact.reload.approval_status).to eq("in_review")
    expect(Notification.where(user: reviewer_a, kind: "review_requested")).to exist
  end

  it "KHÔNG cho người ngoài danh sách reviewer quyết định" do
    round = submit!([reviewer_a])
    expect {
      Approvals::Decide.call(round: round, user: outsider, decision: "approved")
    }.to raise_error(ArgumentError, /không được chỉ định/)
  end

  it "một reviewer chỉ quyết định MỘT lần cho một round" do
    round = submit!([reviewer_a])
    Approvals::Decide.call(round: round, user: reviewer_a, decision: "approved")
    expect {
      Approvals::Decide.call(round: round, user: reviewer_a, decision: "rejected")
    }.to raise_error(ArgumentError, /(đã có quyết định|đã kết thúc)/)
    expect(round.reload.status).to eq("approved")
  end

  it "rejected thắng approved; artifact sync trạng thái của round mới nhất" do
    round = submit!([reviewer_a, reviewer_b])
    Approvals::Decide.call(round: round, user: reviewer_a, decision: "approved")
    expect(round.reload.status).to eq("pending") # reviewer_b chua quyet — round con mo
    Approvals::Decide.call(round: round, user: reviewer_b, decision: "rejected")
    expect(round.reload.status).to eq("rejected")
    expect(artifact.reload.approval_status).to eq("rejected")
  end

  it "round đã kết thúc không nhận quyết định mới" do
    round = submit!([reviewer_a])
    Approvals::Decide.call(round: round, user: reviewer_a, decision: "changes_requested")
    expect(round.reload.status).to eq("changes_requested")
    expect {
      Approvals::Decide.call(round: round, user: reviewer_b, decision: "approved")
    }.to raise_error(ArgumentError, /đã kết thúc/)
  end

  it "quorum: đủ số lượt approved mới approved" do
    round = Approvals::Submit.call(artifact: artifact, user: editor,
                                   reviewers: [reviewer_a, reviewer_b], quorum: 2)
    Approvals::Decide.call(round: round, user: reviewer_a, decision: "approved")
    expect(round.reload.status).to eq("pending")
    Approvals::Decide.call(round: round, user: reviewer_b, decision: "approved")
    expect(round.reload.status).to eq("approved")
  end

  it "không submit artifact đang in_review" do
    submit!([reviewer_a])
    expect {
      Approvals::Submit.call(artifact: artifact.reload, user: editor, reviewers: [reviewer_b])
    }.to raise_error(ArgumentError, /không thể gửi duyệt/)
  end
end
