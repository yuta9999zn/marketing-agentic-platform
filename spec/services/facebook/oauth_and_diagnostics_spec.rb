require "rails_helper"

RSpec.describe "Facebook OAuth & diagnostics (mocked Graph API)" do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let!(:m) { create(:membership, organization: org, user: user, role: "owner") }

  it "authorize_url dùng endpoint dialog chính thức với scope tối thiểu" do
    with_env("FACEBOOK_APP_ID" => "123", "FACEBOOK_APP_SECRET" => "sec") do
      url = Facebook::Oauth.authorize_url(state: "st", redirect_uri: "https://app.example/facebook/connection/callback")
      expect(url).to start_with("https://www.facebook.com/#{Facebook::Config.graph_version}/dialog/oauth?")
      expect(url).to include("client_id=123", "state=st", "response_type=code")
      expect(CGI.parse(URI.parse(url).query)["scope"].first.split(",")).to match_array(%w[pages_show_list pages_read_engagement pages_manage_posts])
    end
  end

  it "exchange_code đổi code → token dài hạn qua client (stub)" do
    client = instance_double(Facebook::GraphApi::HttpClient, mock?: false)
    allow(client).to receive(:get).with("/oauth/access_token", hash_including(code: "abc"))
                                  .and_return("access_token" => "short", "expires_in" => 3600)
    allow(client).to receive(:get).with("/oauth/access_token", hash_including(grant_type: "fb_exchange_token", fb_exchange_token: "short"))
                                  .and_return("access_token" => "long", "expires_in" => 5_000_000)
    with_env("FACEBOOK_APP_ID" => "123", "FACEBOOK_APP_SECRET" => "sec") do
      Facebook::GraphApi.with_client(client) do
        res = Facebook::Oauth.exchange_code(code: "abc", redirect_uri: "https://x/cb")
        expect(res[:token]).to eq("long")
        expect(res[:expires_at]).to be > 50.days.from_now
      end
    end
  end

  it "BeginAuthorization lưu page token mã hoá, không lộ token trong pages" do
    auth = Facebook::BeginAuthorization.call(user: user, org: org, code: "mock", redirect_uri: "https://x/cb",
                                             page_hint: "https://www.facebook.com/marketflow.demo", mode: "mock")
    expect(auth.pages.first.keys).not_to include("access_token")
    expect(auth.page_token("100000000000001")).to eq("mock_page_token_1")
    expect(auth.to_json).not_to include("mock_page_token")
    expect(auth.hinted_page["id"]).to eq("100000000000001")
  end

  it "Diagnostics báo thiếu quyền và vai trò, cập nhật status kết nối" do
    conn = create(:facebook_page_connection, organization: org, granted_scopes: %w[pages_show_list], page_tasks: %w[ANALYZE])
    report = Facebook::Diagnostics.call(conn, remote: false)
    expect(report.ok?).to be false
    expect(report.issues.map(&:code)).to include(:missing_scopes, :missing_page_role)
    expect(conn.reload.status).to eq("permission_missing")
  end

  it "Diagnostics remote: token hết hạn (190) → token_expired" do
    conn = create(:facebook_page_connection, organization: org, connection_mode: "live")
    client = instance_double(Facebook::GraphApi::HttpClient, mock?: false)
    allow(client).to receive(:get).with("/debug_token", anything).and_raise(Facebook::ApiError.new("expired", code: 190))
    with_env("FACEBOOK_APP_ID" => "1", "FACEBOOK_APP_SECRET" => "s") do
      Facebook::GraphApi.with_client(client) do
        report = Facebook::Diagnostics.call(conn, remote: true)
        expect(report.issues.map(&:code)).to include(:token_expired)
      end
    end
    expect(conn.reload.status).to eq("token_expired")
  end

  it "HttpClient parse lỗi Meta thành ApiError phân loại, không log token" do
    client = Facebook::GraphApi::HttpClient.new
    body = { error: { message: "Error validating access token", type: "OAuthException", code: 190, error_subcode: 463, fbtrace_id: "AbC" } }.to_json
    response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    allow(response).to receive(:body).and_return(body)
    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
    expect { client.get("/me", access_token: "EAAx") }.to raise_error(Facebook::ApiError) { |e|
      expect(e.code).to eq(190)
      expect(e.kind).to eq(:token_expired)
      expect(e.fbtrace_id).to eq("AbC")
    }
  end

  it "HttpClient: timeout → NetworkError (tạm thời)" do
    client = Facebook::GraphApi::HttpClient.new
    allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Net::OpenTimeout)
    expect { client.get("/me", access_token: "x") }.to raise_error(Facebook::NetworkError)
  end
end
