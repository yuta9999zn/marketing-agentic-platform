require "rails_helper"

# Request spec cho luồng OAuth. Mock mode: không gọi Meta; luồng state/nonce,
# quyền và lưu token vẫn chạy thật.
RSpec.describe "Facebook connection", type: :request do
  let(:org) { create(:organization) }
  let(:owner) { create(:user) }
  let(:copywriter) { create(:user) }
  let(:client_user) { create(:user) }
  let!(:m1) { create(:membership, organization: org, user: owner, role: "owner") }
  let!(:m2) { create(:membership, organization: org, user: copywriter, role: "copywriter") }
  let!(:m3) { create(:membership, organization: org, user: client_user, role: "client") }

  around { |ex| with_env("FACEBOOK_MOCK_MODE" => "true") { ex.run } }

  it "owner: dán link fanpage → start → callback → tự chọn đúng Page, token mã hoá, audit" do
    login_as(owner)
    post start_facebook_connection_path, params: { page_url: "https://www.facebook.com/marketflow.demo" }
    expect(response).to redirect_to(%r{/facebook/connection/callback\?code=mock_code&state=})
    expect(session[:facebook_oauth_nonce]).to be_present

    get response.location
    expect(response).to redirect_to(facebook_connection_path)
    follow_redirect!
    expect(response.body).to include("MarketFlow Demo Page")

    conn = org.facebook_page_connections.first
    expect(conn.page_id).to eq("100000000000001")
    expect(conn.status).to eq("connected")
    expect(conn.access_token_ciphertext).to be_present
    expect(conn.access_token_ciphertext).not_to include("mock_page_token")
    expect(response.body).not_to include("mock_page_token") # token không ra frontend
    expect(session[:facebook_oauth_nonce]).to be_nil
    expect(AuditLog.where(action: "facebook.page.connected").count).to eq(1)
    expect(FacebookAuthorization.count).to eq(0) # bản tạm đã xoá
  end

  it "không có gợi ý Page → hiện danh sách để chọn; select_page kết nối" do
    login_as(owner)
    post start_facebook_connection_path
    get response.location
    follow_redirect!
    expect(response.body).to include("Cửa hàng Demo")
    expect(FacebookAuthorization.active.count).to eq(1)
    post select_page_facebook_connection_path, params: { page_id: "100000000000002" }
    expect(org.facebook_page_connections.first.page_name).to eq("Cửa hàng Demo")
  end

  it "callback với state giả mạo bị từ chối, không tạo kết nối, có audit" do
    login_as(owner)
    get callback_facebook_connection_path(code: "mock_code", state: "forged")
    expect(response).to redirect_to(facebook_connection_path)
    expect(org.facebook_page_connections.count).to eq(0)
    expect(AuditLog.where(action: "facebook.oauth.state_rejected").count).to eq(1)
  end

  it "callback với state hợp lệ nhưng từ trình duyệt khác (không có nonce trong session) bị từ chối" do
    login_as(owner)
    state = Facebook::OauthState.generate(user: owner, org: org, nonce: "n1", mode: "mock")
    get callback_facebook_connection_path(code: "mock_code", state: state)
    expect(org.facebook_page_connections.count).to eq(0)
    expect(flash[:alert]).to be_present
  end

  it "người dùng từ chối ở Facebook → không kết nối, báo lỗi" do
    login_as(owner)
    post start_facebook_connection_path
    state = CGI.parse(URI.parse(response.location).query)["state"].first
    get callback_facebook_connection_path(error: "access_denied", error_reason: "user_denied", state: state)
    expect(org.facebook_page_connections.count).to eq(0)
    expect(flash[:alert]).to include("từ chối")
  end

  it "copywriter (không có quyền manage) không bắt đầu OAuth được; client bị chặn hẳn" do
    login_as(copywriter)
    post start_facebook_connection_path
    expect(response).to redirect_to(root_path)
    get facebook_connection_path
    expect(response).to have_http_status(:ok) # xem được trạng thái

    login_as(client_user)
    get facebook_connection_path
    expect(response).to redirect_to(root_path)
  end

  it "kill switch chỉ admin; disconnect xoá token" do
    login_as(owner)
    post start_facebook_connection_path, params: { page_url: "100000000000001" }
    get response.location
    post kill_switch_facebook_connection_path(paused: true)
    expect(org.reload.facebook_publishing_paused).to be true
    delete facebook_connection_path
    expect(org.facebook_page_connections.first.status).to eq("disconnected")
    expect(org.facebook_page_connections.first.access_token_ciphertext).to be_nil

    login_as(copywriter)
    post kill_switch_facebook_connection_path(paused: false)
    expect(org.reload.facebook_publishing_paused).to be true
  end

  it "chưa cấu hình Meta app và không mock → start báo lỗi rõ" do
    login_as(owner)
    with_env("FACEBOOK_MOCK_MODE" => nil, "FACEBOOK_APP_ID" => nil, "FACEBOOK_APP_SECRET" => nil) do
      post start_facebook_connection_path, params: { page_url: "https://www.facebook.com/x" }
      expect(flash[:alert]).to include("Chưa cấu hình")
    end
  end

  it "live mode: start redirect sang dialog Meta với state ký" do
    login_as(owner)
    with_env("FACEBOOK_MOCK_MODE" => nil, "FACEBOOK_APP_ID" => "123", "FACEBOOK_APP_SECRET" => "sec") do
      post start_facebook_connection_path, params: { page_url: "https://www.facebook.com/x" }
      expect(response.location).to start_with("https://www.facebook.com/")
      expect(response.location).to include("client_id=123", "state=")
    end
  end
end
