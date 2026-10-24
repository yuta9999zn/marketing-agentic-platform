require "rails_helper"

RSpec.describe "Dashboard overview", type: :request do
  let(:org) { create(:organization) }
  let(:owner) { create(:user) }
  let(:client_user) { create(:user) }
  let!(:m1) { create(:membership, organization: org, user: owner, role: "owner") }
  let!(:m2) { create(:membership, organization: org, user: client_user, role: "client") }

  it "render hero, KPI, biểu đồ, kênh, lịch đăng với dữ liệu thật" do
    conn = create(:facebook_page_connection, organization: org, page_name: "Page Của Tôi")
    sched = create(:facebook_post, organization: org, facebook_page_connection: conn, title: "Bài lịch")
    sched.update_columns(status: "scheduled", scheduled_at: 1.day.from_now)
    pub = create(:facebook_post, organization: org, facebook_page_connection: conn, title: "Bài đã đăng")
    pub.update_columns(status: "published", published_at: 1.day.ago, facebook_post_id: "1_2", published_via: "mock")
    create(:artifact, campaign: create(:campaign, organization: org))

    login_as(owner)
    get root_path
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("Tăng trưởng thương hiệu")
    expect(body).to include("Page Của Tôi")
    expect(body).to include("Bài lịch")
    expect(body).to include("Bài đã đăng")
    expect(body).to include("line-chart")
    expect(body).to include("Facebook Fanpage")
  end

  it "client (campaign-scoped) không thấy khối Facebook/kênh, không lỗi" do
    login_as(client_user)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("/facebook/connection")
  end
end
