require "rails_helper"

# Phase 3 — endpoint dịch nhanh (JSON). Phân quyền phải trả JSON 403,
# KHÔNG redirect (fetch không hiểu redirect).
RSpec.describe "Dịch nhanh", type: :request do
  let(:org) { create(:organization) }
  let(:manager) { create(:user) }
  let(:client_user) { create(:user) }
  let(:client) { create(:client, organization: org) }
  let(:campaign) { create(:campaign, organization: org, client: client) }
  let(:other_campaign) { create(:campaign, organization: org, client: client, name: "Campaign khác") }

  before do
    create(:membership, organization: org, user: manager, role: "manager")
    create(:membership, organization: org, user: client_user, role: "client")
  end

  def body = JSON.parse(response.body)

  it "người nội bộ dịch được, trả JSON" do
    login_as(manager)
    allow(Translations::QuickTranslate).to receive(:call)
      .and_return(Translations::QuickTranslate::Result.new(text: "Hello", provider: "translation_fake", truncated: false))

    post quick_translate_path, params: { text: "Xin chào", target_locale: "en" }
    expect(response).to have_http_status(:ok)
    expect(body["ok"]).to be true
    expect(body["text"]).to eq("Hello")
  end

  it "khách được mời dịch được nội dung của CHÍNH campaign đó" do
    CampaignCollaborator.create!(campaign: campaign, user: client_user, access: "view")
    login_as(client_user)
    allow(Translations::QuickTranslate).to receive(:call)
      .and_return(Translations::QuickTranslate::Result.new(text: "Hi", provider: "x", truncated: false))

    post quick_translate_path, params: { text: "Xin chào", campaign_id: campaign.id }
    expect(response).to have_http_status(:ok)
    expect(body["ok"]).to be true
  end

  it "khách KHÔNG dịch được nội dung campaign chưa được mời — 403 JSON, không redirect" do
    CampaignCollaborator.create!(campaign: campaign, user: client_user, access: "view")
    login_as(client_user)

    post quick_translate_path, params: { text: "Xin chào", campaign_id: other_campaign.id }
    expect(response).to have_http_status(:forbidden)
    expect(body["ok"]).to be false
  end

  it "khách không gửi kèm campaign_id thì bị từ chối (khu vực nội bộ)" do
    login_as(client_user)
    post quick_translate_path, params: { text: "Xin chào" }
    expect(response).to have_http_status(:forbidden)
  end

  it "campaign của tổ chức khác trả 404, không lộ tồn tại" do
    foreign = create(:campaign, organization: create(:organization))
    login_as(manager)
    post quick_translate_path, params: { text: "x", campaign_id: foreign.id }
    expect(response).to have_http_status(:not_found)
  end

  it "chuỗi rỗng trả 422" do
    login_as(manager)
    post quick_translate_path, params: { text: "   " }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(body["ok"]).to be false
  end

  it "model hỏng thì trả 503 và nói thật, KHÔNG trả bản dịch giả" do
    login_as(manager)
    allow(Translations::QuickTranslate).to receive(:call)
      .and_raise(CDFLHarness::Errors::AdapterError, "ollama unreachable")

    post quick_translate_path, params: { text: "Xin chào" }
    expect(response).to have_http_status(:service_unavailable)
    expect(body["ok"]).to be false
    expect(body["error"]).to include("ollama unreachable")
  end

  it "locale đích lạ rơi về mặc định en" do
    login_as(manager)
    expect(Translations::QuickTranslate).to receive(:call)
      .with(hash_including(target_locale: "en"))
      .and_return(Translations::QuickTranslate::Result.new(text: "t", provider: "p", truncated: false))

    post quick_translate_path, params: { text: "x", target_locale: "klingon" }
  end
end
