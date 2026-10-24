require "rails_helper"

# Phase 1 — thư viện template: CRUD prompt template, lưu campaign thành mẫu,
# tạo campaign từ mẫu (clone cả artifact).
RSpec.describe "Thư viện template", type: :request do
  let(:org) { create(:organization) }
  let(:manager) { create(:user) }
  let(:copywriter) { create(:user) }
  let(:client_user) { create(:user) }
  let!(:client) { create(:client, organization: org) }

  before do
    create(:membership, organization: org, user: manager, role: "manager")
    create(:membership, organization: org, user: copywriter, role: "copywriter")
    create(:membership, organization: org, user: client_user, role: "client")
  end

  describe "prompt template CRUD" do
    it "manager tạo được prompt template" do
      login_as(manager)
      expect {
        post prompt_templates_path, params: { prompt_template: {
          name: "Kịch bản video", category: "video_script",
          instructions: "Hook 3 giây đầu", locale: "vi"
        } }
      }.to change(PromptTemplate, :count).by(1)
      expect(response).to redirect_to(templates_path)
      expect(PromptTemplate.last.organization).to eq(org)
    end

    it "từ chối category ngoài whitelist" do
      login_as(manager)
      post prompt_templates_path, params: { prompt_template: { name: "X", category: "hack" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PromptTemplate.count).to eq(0)
    end

    it "sửa hướng dẫn thì tăng version; sửa tên thì không" do
      login_as(manager)
      pt = PromptTemplate.create!(organization: org, name: "A", category: "email",
                                  instructions: "cũ", owner: manager)

      patch prompt_template_path(pt), params: { prompt_template: {
        name: "A", category: "email", instructions: "mới"
      } }
      expect(pt.reload.version).to eq(2)

      patch prompt_template_path(pt), params: { prompt_template: {
        name: "B", category: "email", instructions: "mới"
      } }
      expect(pt.reload.version).to eq(2)
      expect(pt.name).to eq("B")
    end

    it "copywriter (edit) tạo được nhưng không xóa được" do
      pt = PromptTemplate.create!(organization: org, name: "A", category: "email", owner: manager)
      login_as(copywriter)
      delete prompt_template_path(pt)
      expect(response).to redirect_to(root_path)
      expect(PromptTemplate.exists?(pt.id)).to be true
    end

    it "client bị chặn khỏi toàn bộ khu vực template" do
      pt = PromptTemplate.create!(organization: org, name: "A", category: "email", owner: manager)
      login_as(client_user)
      get templates_path
      expect(response).to redirect_to(root_path)
      get new_prompt_template_path
      expect(response).to redirect_to(root_path)
      post prompt_templates_path, params: { prompt_template: { name: "X", category: "email" } }
      expect(PromptTemplate.count).to eq(1)
      delete prompt_template_path(pt)
      expect(PromptTemplate.exists?(pt.id)).to be true
    end

    it "không sửa được prompt template của org khác" do
      other_org = create(:organization)
      foreign = PromptTemplate.create!(organization: other_org, name: "Ngoài", category: "email")
      login_as(manager)
      patch prompt_template_path(foreign), params: { prompt_template: { name: "Đổi" } }
      expect(response).to redirect_to(root_path)
      expect(foreign.reload.name).to eq("Ngoài")
    end
  end

  describe "lưu campaign thành template" do
    let(:campaign) { create(:campaign, organization: org, client: client, start_date: Date.new(2026, 3, 1)) }

    before do
      m = campaign.milestones.create!(title: "Sản xuất", due_at: Time.zone.local(2026, 3, 11), position: 0)
      campaign.tasks.create!(title: "Viết bài", due_date: Date.new(2026, 3, 6), milestone: m, priority: "high")
      campaign.artifacts.create!(kind: "social_post", title: "Bài mẫu", body: "Nội dung",
                                 approval_status: "approved")
      campaign.artifacts.create!(kind: "social_post", title: "Bản nháp", body: "Chưa duyệt",
                                 approval_status: "draft")
    end

    it "đóng gói milestone/task theo offset ngày và chỉ lấy artifact đã duyệt" do
      login_as(manager)
      post save_as_template_campaign_path(campaign), params: { name: "Mẫu social" }

      template = ProjectTemplate.find_by(name: "Mẫu social")
      expect(template).to be_present
      expect(template.config["milestones"]).to eq([{ "title" => "Sản xuất", "offset_days" => 10 }])
      expect(template.config["tasks"].first).to include("title" => "Viết bài", "offset_days" => 5,
                                                        "milestone" => "Sản xuất")
      expect(template.config["artifacts"].map { |a| a["title"] }).to eq(["Bài mẫu"])
    end

    it "bỏ qua artifact khi người dùng không tick" do
      login_as(manager)
      post save_as_template_campaign_path(campaign), params: { name: "Không kèm", include_artifacts: "0" }
      expect(ProjectTemplate.find_by(name: "Không kèm").config["artifacts"]).to eq([])
    end

    it "copywriter không lưu được (cần quyền manage)" do
      login_as(copywriter)
      post save_as_template_campaign_path(campaign), params: { name: "Trộm" }
      expect(ProjectTemplate.find_by(name: "Trộm")).to be_nil
    end
  end

  describe "chọn prompt template khi tạo nháp AI" do
    let(:campaign) { create(:campaign, organization: org, client: client) }

    it "dùng template trong org và ghi lại phiên bản" do
      template = PromptTemplate.create!(organization: org, name: "Bài social", category: "social_post",
                                        instructions: "Hook đứng độc lập", owner: manager)
      login_as(manager)
      post generate_campaign_path(campaign), params: { kind: "social_post", prompt_template_id: template.id }

      expect(AiRun.last.prompt_template_version).to eq("Bài social v1")
      expect(Artifact.last.ai_metadata["prompt_template_id"]).to eq(template.id)
    end

    it "bỏ qua prompt template của tổ chức khác" do
      foreign = PromptTemplate.create!(organization: create(:organization), name: "Ngoài",
                                       category: "social_post", instructions: "Không được dùng")
      login_as(manager)
      post generate_campaign_path(campaign), params: { kind: "social_post", prompt_template_id: foreign.id }

      expect(AiRun.last.prompt_template_version).to be_nil
      expect(Artifact.last.ai_metadata["prompt_template_id"]).to be_nil
    end
  end

  describe "tạo campaign từ template" do
    it "clone artifact mẫu về trạng thái draft, không kế thừa approved" do
      template = org.project_templates.create!(name: "Mẫu", owner: manager, config: {
        "milestones" => [{ "title" => "M1", "offset_days" => 3 }],
        "tasks" => [{ "title" => "T1", "offset_days" => 1, "milestone" => "M1" }],
        "artifacts" => [{ "kind" => "social_post", "title" => "Bài mẫu", "body" => "Nội dung mẫu" }]
      })

      login_as(manager)
      post create_from_template_campaigns_path, params: {
        template_id: template.id, client_id: client.id, name: "Campaign mới",
        start_date: "2026-05-01"
      }

      campaign = Campaign.find_by(name: "Campaign mới")
      expect(campaign.milestones.pluck(:title)).to eq(["M1"])
      expect(campaign.tasks.pluck(:title)).to eq(["T1"])

      artifact = campaign.artifacts.find_by(title: "Bài mẫu")
      expect(artifact.approval_status).to eq("draft")
      expect(artifact.body).to eq("Nội dung mẫu")
      expect(artifact.source_note).to include("Mẫu")
    end

    it "không mutate template gốc" do
      template = org.project_templates.create!(name: "Gốc", owner: manager, config: {
        "artifacts" => [{ "kind" => "email", "title" => "Email mẫu", "body" => "Xin chào" }]
      })
      before_config = template.config.deep_dup

      login_as(manager)
      post create_from_template_campaigns_path, params: {
        template_id: template.id, client_id: client.id, name: "C1"
      }
      expect(template.reload.config).to eq(before_config)
    end
  end
end
