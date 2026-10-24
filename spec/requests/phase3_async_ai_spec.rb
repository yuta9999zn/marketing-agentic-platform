require "rails_helper"

# Phase 3 — request web KHÔNG được chạy AI đồng bộ khi provider là model thật:
# nạp model + sinh chữ mất 20-90 giây, người dùng sẽ ngồi nhìn trang treo.
RSpec.describe "AI chạy nền từ giao diện", type: :request do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:client) { create(:client, organization: org) }
  let(:campaign) { create(:campaign, organization: org, client: client) }

  before { create(:membership, organization: org, user: user, role: "manager") }

  def stub_ready(ready: true, detail: :ok)
    allow(Ai::Availability).to receive(:status)
      .and_return(Ai::Availability::Status.new(provider: "ollama", model: "qwen2.5:7b",
                                               ready: ready, detail: detail))
  end

  def with_ollama(&block) = with_env("AI_PROVIDER" => "ollama", "OLLAMA_MODEL" => nil, &block)

  describe "tạo nháp" do
    it "provider chậm → xếp job, KHÔNG chạy AI trong request" do
      with_ollama do
        stub_ready
        login_as(user)
        expect(Ai::Workflows::ScriptDraft).not_to receive(:call)

        expect {
          post generate_campaign_path(campaign), params: { kind: "social_post", channel: "facebook" }
        }.to have_enqueued_job(AiDraftJob).with(hash_including(kind: "social_post"))
        expect(response).to redirect_to(campaign_path(campaign, anchor: "stage-content"))
      end
    end

    it "provider fake → chạy ngay, tạo artifact trong request" do
      login_as(user)
      expect {
        post generate_campaign_path(campaign), params: { kind: "social_post" }
      }.to change(Artifact, :count).by(1)
    end

    it "AI không sẵn sàng → báo lỗi, không xếp job, không tạo gì" do
      with_ollama do
        stub_ready(ready: false, detail: :unreachable)
        login_as(user)
        expect {
          post generate_campaign_path(campaign), params: { kind: "social_post" }
        }.to not_have_enqueued_job(AiDraftJob).and(not_change_artifact_count)
        expect(flash[:alert]).to be_present
      end
    end

    it "loại nội dung lạ bị chặn trước khi chạm tới AI" do
      login_as(user)
      expect {
        post generate_campaign_path(campaign), params: { kind: "rm -rf" }
      }.not_to change(Artifact, :count)
      expect(flash[:alert]).to be_present
    end
  end

  describe "dịch artifact" do
    let(:artifact) { campaign.artifacts.create!(kind: "social_post", title: "Gốc", body: "Nội dung") }

    it "provider chậm → xếp job" do
      with_ollama do
        stub_ready
        login_as(user)
        expect {
          post translate_artifact_path(artifact), params: { target_locale: "en" }
        }.to have_enqueued_job(ArtifactTranslationJob)
      end
    end

    it "provider fake → dịch ngay" do
      artifact # tạo artifact nguồn TRƯỚC khi đo, nếu không đếm cả nó
      login_as(user)
      expect {
        post translate_artifact_path(artifact), params: { target_locale: "en" }
      }.to change(Artifact, :count).by(1)
      expect(Artifact.last.kind).to eq("translation")
    end
  end

  describe "prompt ảnh" do
    it "provider chậm → xếp job (bước này riêng nó mất ~50 giây)" do
      with_ollama do
        stub_ready
        login_as(user)
        expect {
          post create_image_prompt_campaign_path(campaign), params: { objective: "mùa hè" }
        }.to have_enqueued_job(ImagePromptJob)
      end
    end

    it "provider fake → tạo ngay" do
      login_as(user)
      expect {
        post create_image_prompt_campaign_path(campaign), params: { objective: "mùa hè" }
      }.to change(Artifact, :count).by(1)
    end
  end

  # Matcher phụ cho phép nối .and(...)
  def not_have_enqueued_job(job) = have_enqueued_job(job).exactly(0).times
  def not_change_artifact_count = change(Artifact, :count).by(0)
end
