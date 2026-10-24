require "rails_helper"

# Phase 0 specs: fail-closed authorization + tenant isolation.
# Mọi request bị từ chối KHÔNG được thay đổi database.
RSpec.describe "P0 authorization", type: :request do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let!(:client_user) { create(:user) }
  let!(:client_membership) { create(:membership, organization: org, user: client_user, role: "client") }
  let(:org_client_record) { create(:client, organization: org) }
  let(:campaign) { create(:campaign, organization: org, client: org_client_record) }
  let(:pending_artifact) { create(:artifact, campaign: campaign, approval_status: "draft", kind: "persona") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(client_user)
    allow_any_instance_of(ApplicationController).to receive(:current_organization).and_return(org)
    allow_any_instance_of(ApplicationController).to receive(:current_role).and_return("client")
  end

  it "client KHÔNG được duyệt artifact — POST approvals với round THẬT không ghi database" do
    approver = create(:user)
    create(:membership, organization: org, user: approver, role: "approver")
    editor = create(:user)
    create(:membership, organization: org, user: editor, role: "copywriter")
    round = Approvals::Submit.call(artifact: pending_artifact, user: editor, reviewers: [approver])

    expect {
      post approvals_path, params: { round_id: round.id, decision: "approved" }
    }.not_to change(ApprovalDecision, :count)
    expect(round.reload.status).to eq("pending")
    expect(pending_artifact.reload.approval_status).to eq("in_review")
    expect(response).to redirect_to(root_path)
  end

  it "client KHÔNG tạo task trong campaign chưa được mời — không ghi database" do
    expect {
      post tasks_path, params: { task: { campaign_id: campaign.id, title: "Lén tạo task" } }
    }.not_to change(Task, :count)
    expect(response).to redirect_to(root_path)
  end

  it "client KHÔNG comment trong campaign chưa được mời" do
    expect {
      post comments_path, params: { comment: { campaign_id: campaign.id, body: "spam" } }
    }.not_to change(Comment, :count)
  end

  it "client được mời (access=comment) comment được nhưng không edit artifact" do
    campaign.campaign_collaborators.create!(user: client_user, access: "comment")
    expect {
      post comments_path, params: { comment: { campaign_id: campaign.id, body: "Góp ý từ client" } }
    }.to change(Comment, :count).by(1)

    expect {
      patch artifact_path(pending_artifact), params: { artifact: { body: "client sửa" } }
    }.not_to change { pending_artifact.reload.version }
  end

  it "client KHÔNG tạo campaign dù gửi client_id hợp lệ" do
    expect {
      post campaigns_path, params: { campaign: { client_id: org_client_record.id, name: "Lén tạo" } }
    }.not_to change(Campaign, :count)
  end
end

RSpec.describe "P0 tenant isolation", type: :request do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:manager) { create(:user) }
  let!(:membership) { create(:membership, organization: org, user: manager, role: "manager") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(manager)
    allow_any_instance_of(ApplicationController).to receive(:current_organization).and_return(org)
    allow_any_instance_of(ApplicationController).to receive(:current_role).and_return("manager")
  end

  it "không tạo campaign với client_id của organization khác" do
    foreign_client = create(:client, organization: other_org)
    expect {
      post campaigns_path, params: { campaign: { client_id: foreign_client.id, name: "Cross tenant" } }
    }.to change(Campaign, :count).by(0)
  end

  it "không gán task cho user ngoài organization" do
    campaign = create(:campaign, organization: org)
    foreign_user = create(:user)
    create(:membership, organization: other_org, user: foreign_user)
    expect {
      post tasks_path, params: { task: { campaign_id: campaign.id, title: "Task", assignee_id: foreign_user.id } }
    }.to change(Task, :count).by(1)
    expect(Task.last.assignee_id).to be_nil
  end

  it "không comment với artifact_id của campaign khác" do
    campaign = create(:campaign, organization: org)
    other_campaign = create(:campaign, organization: other_org)
    foreign_artifact = create(:artifact, campaign: other_campaign)
    expect {
      post comments_path, params: { comment: { campaign_id: campaign.id, body: "x", artifact_id: foreign_artifact.id } }
    }.not_to change(Comment, :count)
  end

  it "campaign model từ chối client thuộc organization khác" do
    foreign_client = create(:client, organization: other_org)
    bad = build(:campaign, organization: org, client: foreign_client)
    expect(bad).not_to be_valid
    expect(bad.errors[:client]).to be_present
  end
end
