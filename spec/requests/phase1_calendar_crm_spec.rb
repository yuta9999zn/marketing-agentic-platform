require "rails_helper"

# Phase 1 — content calendar (lịch tháng) và hồ sơ khách hàng (CRM).
RSpec.describe "Lịch nội dung & CRM", type: :request do
  let(:org) { create(:organization) }
  let(:manager) { create(:user) }
  let(:client_user) { create(:user) }
  let!(:client) { create(:client, organization: org, name: "ACME") }
  let!(:campaign) { create(:campaign, organization: org, client: client, name: "Chiến dịch hè") }

  before do
    create(:membership, organization: org, user: manager, role: "manager")
    create(:membership, organization: org, user: client_user, role: "client")
  end

  describe "content calendar" do
    it "gộp sự kiện, task đến hạn và nội dung dự kiến đăng trong tháng" do
      travel_to Time.zone.local(2026, 6, 15, 9, 0) do
        create(:event, campaign: campaign, title: "Họp kickoff",
                       starts_at: Time.zone.local(2026, 6, 20, 14, 0),
                       ends_at: Time.zone.local(2026, 6, 20, 15, 0))
        campaign.tasks.create!(title: "Nộp bài viết", assignee: manager, due_date: Date.new(2026, 6, 22))
        campaign.artifacts.create!(kind: "social_post", title: "Bài Facebook",
                                   due_date: Date.new(2026, 6, 25), channel: "facebook")

        login_as(manager)
        get calendar_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Họp kickoff", "Nộp bài viết", "Bài Facebook")
      end
    end

    it "chuyển tháng chỉ hiện mục của tháng đó" do
      create(:event, campaign: campaign, title: "Sự kiện tháng 7",
                     starts_at: Time.zone.local(2026, 7, 10, 9, 0),
                     ends_at: Time.zone.local(2026, 7, 10, 10, 0))
      login_as(manager)

      get calendar_path, params: { month: "2026-07" }
      expect(response.body).to include("Sự kiện tháng 7")

      get calendar_path, params: { month: "2026-08" }
      expect(response.body).not_to include("Sự kiện tháng 7")
    end

    it "tham số tháng sai định dạng rơi về tháng hiện tại, không raise" do
      login_as(manager)
      get calendar_path, params: { month: "hack; DROP TABLE" }
      expect(response).to have_http_status(:ok)

      get calendar_path, params: { month: "2026-99" }
      expect(response).to have_http_status(:ok)
    end

    it "client không vào được lịch workspace" do
      login_as(client_user)
      get calendar_path
      expect(response).to redirect_to(root_path)
    end

    it "không hiện dữ liệu của campaign ngoài phạm vi truy cập" do
      other_org = create(:organization)
      other_client = create(:client, organization: other_org)
      other_campaign = create(:campaign, organization: other_org, client: other_client)
      create(:event, campaign: other_campaign, title: "Sự kiện tổ chức khác",
                     starts_at: 3.days.from_now, ends_at: 3.days.from_now + 1.hour)

      login_as(manager)
      get calendar_path
      expect(response.body).not_to include("Sự kiện tổ chức khác")
    end
  end

  describe "hồ sơ khách hàng" do
    it "hiện campaign, góp ý và quyết định duyệt từ phía khách" do
      CampaignCollaborator.create!(campaign: campaign, user: client_user, access: "approve")
      campaign.comments.create!(user: client_user, body: "Cần chỉnh tiêu đề")
      artifact = campaign.artifacts.create!(kind: "social_post", title: "Bài đăng", body: "x")
      round = artifact.approval_rounds.create!(artifact_version: artifact.version, requester: manager,
                                               reviewer_ids: [client_user.id], status: "pending")
      round.approval_decisions.create!(user: client_user, decision: "approved")

      login_as(manager)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Chiến dịch hè", "Cần chỉnh tiêu đề", "Bài đăng")
    end

    it "không lẫn góp ý của campaign thuộc khách hàng khác" do
      other_client = create(:client, organization: org, name: "Khách khác")
      other_campaign = create(:campaign, organization: org, client: other_client)
      CampaignCollaborator.create!(campaign: other_campaign, user: client_user, access: "comment")
      other_campaign.comments.create!(user: client_user, body: "Góp ý của khách khác")

      login_as(manager)
      get client_path(client)
      expect(response.body).not_to include("Góp ý của khách khác")
    end

    it "cập nhật được thông tin liên hệ" do
      login_as(manager)
      patch client_path(client), params: { client: {
        name: "ACME", contact_name: "Chị Mai", contact_email: "mai@acme.test", contact_phone: "0900"
      } }
      expect(client.reload.contact_name).to eq("Chị Mai")
      expect(client.contact_email).to eq("mai@acme.test")
    end

    it "từ chối email liên hệ sai định dạng" do
      login_as(manager)
      patch client_path(client), params: { client: { name: "ACME", contact_email: "không-phải-email" } }
      expect(client.reload.contact_email).to be_nil
    end

    it "không xem được khách hàng của tổ chức khác" do
      foreign = create(:client, organization: create(:organization), name: "Khách ngoài")
      login_as(manager)
      get client_path(foreign)
      expect(response).to redirect_to(root_path)
    end

    it "client không vào được CRM" do
      login_as(client_user)
      get client_path(client)
      expect(response).to redirect_to(root_path)
    end
  end
end
