require "rails_helper"

# Phase 3 — tác vụ AI chạy nền. Model chạy trên máy mất 20-90 giây nên
# request web phải trả về ngay và job chạy sau.
RSpec.describe "Job AI chạy nền" do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:client) { create(:client, organization: org) }
  let(:campaign) { create(:campaign, organization: org, client: client) }

  before { create(:membership, organization: org, user: user, role: "manager") }

  describe "AiDraftJob" do
    it "tạo artifact và báo cho người dùng khi xong" do
      expect {
        AiDraftJob.perform_now(kind: "social_post", campaign_id: campaign.id, user_id: user.id,
                               channel: "facebook")
      }.to change(Artifact, :count).by(1)

      note = Notification.last
      expect(note.kind).to eq("ai_draft_ready")
      expect(note.user).to eq(user)
      expect(note.payload["artifact_id"]).to eq(Artifact.last.id)
    end

    it "thất bại thì báo lỗi cho người dùng, KHÔNG im lặng và không ném ra ngoài" do
      allow(Ai::Workflows::ScriptDraft).to receive(:call)
        .and_raise(CDFLHarness::Errors::AdapterError, "ollama unreachable")

      expect {
        AiDraftJob.perform_now(kind: "social_post", campaign_id: campaign.id, user_id: user.id)
      }.not_to raise_error

      note = Notification.last
      expect(note.kind).to eq("ai_draft_failed")
      expect(note.payload["error"]).to include("ollama unreachable")
    end

    it "campaign đã bị xoá thì thoát êm, không tạo gì" do
      expect {
        AiDraftJob.perform_now(kind: "social_post", campaign_id: 999_999, user_id: user.id)
      }.not_to change(Artifact, :count)
    end

    it "chỉ dùng prompt template trong cùng tổ chức" do
      foreign = PromptTemplate.create!(organization: create(:organization), name: "Ngoài",
                                       category: "social_post", instructions: "không được dùng")
      AiDraftJob.perform_now(kind: "social_post", campaign_id: campaign.id, user_id: user.id,
                             prompt_template_id: foreign.id)
      expect(Artifact.last.ai_metadata["prompt_template_id"]).to be_nil
    end

    it "phân tích khảo sát cũng chạy qua job" do
      survey = campaign.surveys.create!(title: "S", status: "open", questions: [{ "key" => "a", "label" => "A?" }])
      survey.survey_responses.create!(answers: { "a" => "trả lời" })

      expect {
        AiDraftJob.perform_now(kind: "survey_insight", campaign_id: campaign.id,
                               user_id: user.id, survey_id: survey.id)
      }.to change(Artifact, :count).by(1)
      expect(Artifact.last.kind).to eq("report")
    end
  end

  describe "ArtifactTranslationJob" do
    it "tạo bản dịch và báo khi xong" do
      source = campaign.artifacts.create!(kind: "social_post", title: "Gốc", body: "Nội dung tiếng Việt")
      expect {
        ArtifactTranslationJob.perform_now(artifact_id: source.id, user_id: user.id, target_locale: "en")
      }.to change(Artifact, :count).by(1)
      expect(Notification.last.kind).to eq("translation_ready")
    end

    it "lỗi thì báo thất bại, không ném ra ngoài" do
      source = campaign.artifacts.create!(kind: "social_post", title: "Gốc", body: "x")
      allow(Translations::CreateService).to receive(:call).and_raise(StandardError, "model chết")

      expect {
        ArtifactTranslationJob.perform_now(artifact_id: source.id, user_id: user.id, target_locale: "en")
      }.not_to raise_error
      expect(Notification.last.kind).to eq("translation_failed")
    end
  end

  describe "ImagePromptJob" do
    it "tạo gói prompt ảnh và báo khi xong" do
      expect {
        ImagePromptJob.perform_now(campaign_id: campaign.id, user_id: user.id,
                                   options: { brand: "ACME", objective: "mùa hè", audience: "trẻ",
                                              channel: "Instagram", dimensions: "1080x1080",
                                              style: "ảnh thật", exclusions: "chữ" })
      }.to change(Artifact, :count).by(1)
      expect(Artifact.last.kind).to eq("image_prompt")
      expect(Notification.last.kind).to eq("image_prompt_ready")
    end
  end

end
