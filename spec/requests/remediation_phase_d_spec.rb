require "rails_helper"

# PHASE D — campaign-scoped reviewer invite + access policy + token table.
RSpec.describe "Remediation Phase D: campaign-scoped reviewer", type: :request do
  let(:org) { create(:organization) }
  let!(:owner) { create(:user) }
  let!(:owner_membership) { create(:membership, organization: org, user: owner, role: "owner") }

  let(:campaign_a) { create(:campaign, organization: org, name: "Campaign A") }
  let(:campaign_b) { create(:campaign, organization: org, name: "Campaign B") }

  def invite_and_accept(email, campaign)
    token = campaign.campaign_collaborator_tokens.create!(email: email, access: "approve", invited_by: owner)
    post accept_campaign_invite_path(token: token.token),
         params: { name: "Reviewer Ngoài", password: "password123" }
    token.reload
    User.find_by(email: email)
  end

  it "model dùng đúng bảng campaign_collaborator_tokens (table rename)" do
    expect(CampaignCollaboratorToken.table_name).to eq("campaign_collaborator_tokens")
    expect(ActiveRecord::Base.connection.table_exists?(:campaign_collaborator_tokens)).to be true
    expect(ActiveRecord::Base.connection.table_exists?(:campaign_collaborators_tokens)).to be false
  end

  it "external reviewer chỉ truy cập campaign được mời, duyệt được artifact của nó" do
    reviewer = invite_and_accept("ext@example.test", campaign_a)
    expect(reviewer.role_in(org)).to eq("external_reviewer")
    collab = campaign_a.campaign_collaborators.find_by(user: reviewer)
    expect(collab.access).to eq("approve")

    login_as(reviewer)

    # Xem campaign A + artifact A OK.
    get campaign_path(campaign_a)
    expect(response).to have_http_status(:ok)

    # Campaign B: hoàn toàn bị chặn.
    get campaign_path(campaign_b)
    expect(response).to redirect_to(root_path)

    # Các trang nội bộ: 302.
    [clients_path, members_path, templates_path, content_studio_path, calendar_path].each do |p|
      get p
      expect(response).to redirect_to(root_path), "expected block at #{p}"
    end

    # Dashboard không leak campaign B.
    campaign_a.artifacts.create!(kind: "social_post", title: "Bài A2", body: "x", approval_status: "in_review")
    get root_path
OLD_IS = nil
    expect(response.body).to include(campaign_a.name)
    expect(response.body).not_to include(campaign_b.name)

    # Duyệt artifact của campaign A qua round thật (session thật).
    artifact = campaign_a.artifacts.create!(kind: "social_post", title: "Bài A", body: "x")
    editor = create(:user)
    create(:membership, organization: org, user: editor, role: "copywriter")
    round = Approvals::Submit.call(artifact: artifact, user: editor, reviewers: [reviewer])

    post approvals_path, params: { round_id: round.id, decision: "approved" }
    expect(round.reload.status).to eq("approved")
    expect(artifact.reload.approval_status).to eq("approved")
  end

  it "token expired/revoked/accepted đều bị từ chối" do
    token = campaign_a.campaign_collaborator_tokens.create!(email: "x@example.test", invited_by: owner)

    token.update!(expires_at: 1.minute.ago)
    get accept_campaign_invite_path(token: token.token)
    expect(response).to redirect_to(login_path)

    token.update!(expires_at: 7.days.from_now, revoked_at: Time.current)
    get accept_campaign_invite_path(token: token.token)
    expect(response).to redirect_to(login_path)

    token.update!(revoked_at: nil, accepted_at: Time.current)
    get accept_campaign_invite_path(token: token.token)
    expect(response).to redirect_to(login_path)
  end

  it "collaborator access=comment KHÔNG được approve; access=approve được" do
    commenter = create(:user)
    create(:membership, organization: org, user: commenter, role: "external_reviewer")
    campaign_a.campaign_collaborators.create!(user: commenter, access: "comment")
    login_as(commenter)

    artifact = campaign_a.artifacts.create!(kind: "social_post", title: "Bài", body: "x")
    editor = create(:user)
    create(:membership, organization: org, user: editor, role: "copywriter")
    round = Approvals::Submit.call(artifact: artifact.reload, user: editor, reviewers: [owner])

    expect {
      post approvals_path, params: { round_id: round.id, decision: "approved" }
    }.not_to change(ApprovalDecision, :count) # policy approve fail-closed
  end

  it "chỉ owner/manager được tạo/revoke campaign invite — không phải editor" do
    editor = create(:user)
    create(:membership, organization: org, user: editor, role: "copywriter")
    login_as(editor)

    expect {
      post campaign_campaign_invites_path(campaign_a), params: { email: "z@example.test" }
    }.not_to change(CampaignCollaboratorToken, :count)
    expect(response).to redirect_to(root_path)
  end
end
