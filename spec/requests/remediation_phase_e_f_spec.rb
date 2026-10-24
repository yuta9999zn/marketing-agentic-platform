require "rails_helper"

# PHASE E + F — route/action runtime bugs + i18n health.
RSpec.describe "Remediation Phase E/F", type: :request do
  let(:org) { create(:organization) }
  let!(:manager) { create(:user) }
  let!(:manager_membership) { create(:membership, organization: org, user: manager, role: "manager") }
  let(:campaign) { create(:campaign, organization: org) }
  let(:other_campaign) { create(:campaign, organization: org) }

  describe "E1 — DELETE collaborator (shallow route) hoạt động" do
    it "manager thu hồi collaborator thành công, client mất quyền ngay" do
      client_user = create(:user)
      create(:membership, organization: org, user: client_user, role: "client")
      collab = campaign.campaign_collaborators.create!(user: client_user, access: "comment")

      login_as(manager)
      expect {
        delete collaborator_path(collab)
      }.to change(CampaignCollaborator, :count).by(-1)
      expect(response).to redirect_to(campaign_path(campaign, anchor: "collaborators"))

      # Client không còn thấy campaign.
      login_as(client_user)
      get campaign_path(campaign)
      expect(response).to redirect_to(root_path)
    end

    it "không xóa được collaborator của campaign organization khác" do
      other_org = create(:organization)
      foreign_campaign = create(:campaign, organization: other_org)
      foreign_user = create(:user)
      create(:membership, organization: other_org, user: foreign_user, role: "client")
      collab = foreign_campaign.campaign_collaborators.create!(user: foreign_user, access: "view")

      login_as(manager)
      expect {
        delete collaborator_path(collab)
      }.not_to change(CampaignCollaborator, :count)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "E2 — POST create_image_prompt" do
    it "editor tạo được image_prompt artifact" do
      login_as(manager)
      expect {
        post create_image_prompt_campaign_path(campaign),
             params: { brand: "ACME", objective: "Ra mắt", audience: "Văn phòng",
                       channel: "Facebook", dimensions: "1080x1080", style: "bright" }
      }.to change { campaign.artifacts.where(kind: "image_prompt").count }.by(1)
      expect(response).to redirect_to(artifact_path(campaign.artifacts.where(kind: "image_prompt").last))
    end

    it "client (được mời view) không tạo được — không mutate" do
      client_user = create(:user)
      create(:membership, organization: org, user: client_user, role: "client")
      campaign.campaign_collaborators.create!(user: client_user, access: "comment")
      login_as(client_user)
      expect {
        post create_image_prompt_campaign_path(campaign), params: { brand: "x" }
      }.not_to change(Artifact, :count)
    end
  end

  describe "E3 — task milestone/dependency scope + cycle" do
    it "milestone của campaign khác bị clear, không cross-campaign" do
      foreign_milestone = other_campaign.milestones.create!(title: "Milestone khác campaign")
      login_as(manager)
      post tasks_path, params: { task: { campaign_id: campaign.id, title: "Task A",
                                         milestone_id: foreign_milestone.id } }
      task = campaign.tasks.find_by(title: "Task A")
      expect(task.milestone_id).to be_nil
    end

    it "task không thể phụ thuộc chính nó" do
      task = campaign.tasks.create!(title: "Self dep")
      task.depends_on_id = task.id
      expect(task).not_to be_valid
    end

    it "không tạo chu trình A → B → A" do
      a = campaign.tasks.create!(title: "A")
      b = campaign.tasks.create!(title: "B", depends_on: a)
      a.depends_on_id = b.id
      expect(a).not_to be_valid
      expect(a.errors[:depends_on]).to be_present
    end
  end

  describe "E4 — set_lifecycle chỉ nhận stage hợp lệ + đúng quyền" do
    it "manager chuyển stage được, audit ghi lại" do
      login_as(manager)
      post set_lifecycle_campaign_path(campaign), params: { stage: "launch" }
      expect(campaign.reload.lifecycle_stage).to eq("launch")
      expect(AuditLog.where(action: "campaign.lifecycle_changed")).to exist
    end

    it "stage lạ bị từ chối" do
      login_as(manager)
      post set_lifecycle_campaign_path(campaign), params: { stage: "hack" }
      expect(campaign.reload.lifecycle_stage).not_to eq("hack")
    end
  end

  describe "F — vi/en dashboard không MissingTranslationData" do
    it "dashboard vi + en đều 200, locale lạ fallback về default" do
      login_as(manager)
      get root_path
      expect(response).to have_http_status(:ok)

      get root_path, params: { locale: "en" }
      expect(response).to have_http_status(:ok)

      get root_path, params: { locale: "de" } # không trong whitelist
      expect(response).to have_http_status(:ok)
      expect(I18n.locale).to eq(:vi)
    end

    it "campaign show + artifact show render date/time không raise" do
      login_as(manager)
      campaign.tasks.create!(title: "T", due_date: Date.current)
      campaign.events.create!(title: "E", starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      artifact = campaign.artifacts.create!(kind: "social_post", title: "S", body: "x")

      [root_path, campaign_path(campaign), artifact_path(artifact)].each do |p|
        get p
        expect(response).to have_http_status(:ok), "failed at #{p}"
      end
    end
  end
end
