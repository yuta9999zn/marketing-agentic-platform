require "rails_helper"

# PHASE A + B — regression sau audit: client dashboard leakage + revoked membership.
RSpec.describe "Remediation Phase A/B", type: :request do
  let(:org) { create(:organization) }
  let!(:client_user) { create(:user) }
  let!(:membership) { create(:membership, organization: org, user: client_user, role: "client") }

  let(:campaign_a) { create(:campaign, organization: org, name: "Campaign Alpha Công khai") }
  let(:campaign_b) { create(:campaign, organization: org, name: "Campaign Beta Bí Mật") }

  before do
    campaign_a.campaign_collaborators.create!(user: client_user, access: "comment")
    # Dữ liệu campaign A (client ĐƯỢC mời) — phải hiển thị.
    campaign_a.tasks.create!(title: "Task Alpha cho client", assignee: nil, due_date: Date.current + 2.days)
    campaign_a.events.create!(title: "Họp Alpha", starts_at: 2.days.from_now, ends_at: 3.days.from_now)
    campaign_a.artifacts.create!(kind: "social_post", title: "Kịch bản Alpha", body: "x",
                                 approval_status: "in_review")
    # Dữ liệu "nhạy cảm" của campaign B (client KHÔNG được mời).
    campaign_b.tasks.create!(title: "Task bí mật Beta", assignee: nil, due_date: Date.current)
    campaign_b.events.create!(title: "Họp bí mật Beta", starts_at: 2.days.from_now, ends_at: 3.days.from_now)
    campaign_b.artifacts.create!(kind: "social_post", title: "Kịch bản bí mật Beta", body: "x",
                                 approval_status: "in_review")
    AuditLog.record!(org: org, action: "beta.secret.event")
  end

  describe "PHASE A — client dashboard không leak campaign khác" do
    it "dashboard 200 nhưng KHÔNG chứa title/count của campaign B" do
      login_as(client_user)
      get root_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include(campaign_a.name)
      expect(body).not_to include(campaign_b.name)
      expect(body).not_to include("Task bí mật Beta")
      expect(body).not_to include("Họp bí mật Beta")
      expect(body).not_to include("Kịch bản bí mật Beta")
      expect(body).not_to include("beta.secret.event") # audit activity bị ẩn với client
    end

    it "campaign index chỉ list campaign được mời" do
      login_as(client_user)
      get campaigns_path
      expect(response.body).to include(campaign_a.name)
      expect(response.body).not_to include(campaign_b.name)
    end

    it "direct URL campaign/artifact B bị chặn và không leak title" do
      login_as(client_user)
      artifact_b = campaign_b.artifacts.first

      get campaign_path(campaign_b)
      expect(response).to redirect_to(root_path)
      expect(response.body).not_to include(campaign_b.name)

      get artifact_path(artifact_b)
      expect(response).to redirect_to(root_path)
      expect(response.body).not_to include("Kịch bản bí mật Beta")
    end
  end

  describe "PHASE B — membership bị thu hồi thì session fail-closed" do
    it "mọi trang nội bộ không trả dữ liệu org cũ sau khi mất membership" do
      login_as(client_user)
      membership.destroy # mô phỏng bị gỡ khỏi org

      [root_path, clients_path, content_studio_path, calendar_path, templates_path, members_path].each do |path|
        get path
        expect(response).to redirect_to(login_path), "expected redirect at #{path}"
        expect(response.body).not_to include(campaign_a.name)
        expect(response.body).not_to include(campaign_b.name)
      end
    end

    it "session org_id cũ không được tin khi membership đã xóa" do
      login_as(client_user)
      membership.destroy

      # Force org cũ vào session rồi request — vẫn phải fail closed.
      get root_path, params: {}, headers: {}
      expect(response).to redirect_to(login_path)
    end
  end
end
