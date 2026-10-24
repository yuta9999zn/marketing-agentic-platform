require "rails_helper"

RSpec.describe "Approvals", type: :request do
  let(:org) { create(:organization) }
  let(:editor) { create(:user) }
  let(:reviewer) { create(:user) }
  let!(:editor_membership) { create(:membership, organization: org, user: editor, role: "copywriter") }
  let!(:reviewer_membership) { create(:membership, organization: org, user: reviewer, role: "approver") }
  let(:campaign) { create(:campaign, organization: org) }
  let(:artifact) { create(:artifact, campaign: campaign, approval_status: "draft") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(reviewer)
    allow_any_instance_of(ApplicationController).to receive(:current_organization).and_return(org)
    allow_any_instance_of(ApplicationController).to receive(:current_role).and_return("approver")
  end

  def open_round
    Approvals::Submit.call(artifact: artifact.reload, user: editor, reviewers: [reviewer])
  end

  it "reviewer được chỉ định duyệt artifact — round kết thúc, artifact approved" do
    round = open_round
    expect {
      post approvals_path, params: { round_id: round.id, decision: "approved" }
    }.to change(ApprovalDecision, :count).by(1)
    expect(round.reload.status).to eq("approved")
    expect(artifact.reload.approval_status).to eq("approved")
  end

  it "reviewer quyết định lần 2 trên cùng round bị từ chối — không thêm decision" do
    round = open_round
    post approvals_path, params: { round_id: round.id, decision: "approved" }
    expect {
      post approvals_path, params: { round_id: round.id, decision: "rejected" }
    }.not_to change(ApprovalDecision, :count)
    expect(round.reload.status).to eq("approved")
  end

  it "editor (không đủ quyền approve) không quyết định được" do
    round = open_round
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(editor)
    allow_any_instance_of(ApplicationController).to receive(:current_role).and_return("copywriter")
    expect {
      post approvals_path, params: { round_id: round.id, decision: "approved" }
    }.not_to change(ApprovalDecision, :count)
    expect(round.reload.status).to eq("pending")
  end
end
