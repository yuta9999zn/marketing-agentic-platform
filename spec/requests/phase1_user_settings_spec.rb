require "rails_helper"

# Phase 1 — cài đặt cá nhân: ngôn ngữ UI + cấu hình nhắc nhở.
RSpec.describe "Cài đặt cá nhân", type: :request do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  before { create(:membership, organization: org, user: user, role: "manager") }

  it "hiển thị trang cài đặt cho mọi role đã đăng nhập" do
    login_as(user)
    get settings_path
    expect(response).to have_http_status(:ok)
  end

  it "lưu ngôn ngữ và áp dụng cho các request sau mà không cần param" do
    login_as(user)
    patch settings_path, params: { user: { locale: "en", reminder_lead_minutes: 1440,
                                           reminder_channel: "in_app" } }
    expect(user.reload.locale).to eq("en")

    get root_path
    expect(response.body).to include("Overview")
    expect(response.body).to include('lang="en"')
  end

  it "param locale ghi đè tùy chọn đã lưu cho riêng request đó" do
    user.update!(locale: "en")
    login_as(user)
    get root_path, params: { locale: "vi" }
    expect(response.body).to include('lang="vi"')
  end

  it "từ chối locale ngoài whitelist" do
    login_as(user)
    patch settings_path, params: { user: { locale: "de", reminder_lead_minutes: 60,
                                           reminder_channel: "in_app" } }
    expect(user.reload.locale).to be_nil
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "từ chối lead time và kênh ngoài whitelist" do
    login_as(user)
    patch settings_path, params: { user: { reminder_lead_minutes: 7, reminder_channel: "sms" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.reminder_lead_minutes).to eq(1440)
    expect(user.reminder_channel).to eq("in_app")
  end

  it "return_to chỉ nhận đường dẫn nội bộ — chặn open redirect" do
    login_as(user)
    patch settings_path, params: { user: { locale: "en" }, return_to: "https://evil.test/steal" }
    expect(response).to redirect_to(settings_path)

    patch settings_path, params: { user: { locale: "vi" }, return_to: "//evil.test" }
    expect(response).to redirect_to(settings_path)

    patch settings_path, params: { user: { locale: "vi" }, return_to: "/calendar" }
    expect(response).to redirect_to("/calendar")
  end

  it "chỉ sửa được chính mình — không nhận user_id từ params" do
    other = create(:user)
    create(:membership, organization: org, user: other, role: "copywriter")
    login_as(user)
    patch settings_path, params: { id: other.id, user: { locale: "en" } }
    expect(user.reload.locale).to eq("en")
    expect(other.reload.locale).to be_nil
  end
end
