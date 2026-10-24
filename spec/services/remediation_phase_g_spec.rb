require "rails_helper"

# PHASE G — honest AI/reminder behavior.
RSpec.describe "Remediation Phase G" do
  let(:org) { create(:organization) }

  describe "task tạo → reminder tự schedule (idempotent)" do
    it "tạo task với assignee + due_date sinh reminder 1 ngày trước hạn" do
      user = create(:user)
      create(:membership, organization: org, user: user, role: "copywriter")
      campaign = create(:campaign, organization: org)
      task = campaign.tasks.create!(title: "Task có hạn", assignee: user,
                                    due_date: Date.current + 5.days)

      expect {
        Reminders::ScheduleForTask.call(task)
      }.to change(Reminder, :count).by(1)
      r = Reminder.last
      expect(r.kind).to eq("task_due_soon")
      expect(r.run_at.to_date).to eq(task.due_date - 1.day)
      expect(r.user).to eq(user)

      # Idempotent: chạy lại không nhân bản.
      expect { Reminders::ScheduleForTask.call(task) }.not_to change(Reminder, :count)
    end
  end

  describe "Ai::Gateway chỉ inject fake khi provider là fake" do
    it "mặc định fake → adapter_override được set" do
      gw = Ai::Gateway.new(org: org, fake_completion: ->(_p) { "{}" })
      expect(gw.config.adapter_override).to be_present
    end

    it "provider ngoài được cấu hình → KHÔNG override fake (fake bị bỏ)" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AI_PROVIDER").and_return("openai")
      allow(ENV).to receive(:[]).with("AI_EXTERNAL_ENABLED").and_return("true")
      allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test-key")

      gw = Ai::Gateway.new(org: org, fake_completion: ->(_p) { "{}" })
      expect(gw.config.adapter_override).to be_nil
      expect(gw.config.provider).to eq(:openai)
    end
  end

  describe "adapter factory: fake mặc định, external thiếu provider → lỗi rõ ràng" do
    it "mặc định trả FakeAdapter" do
      expect(Providers::AdapterFactory.translation_for(org: org)).to be_a(Providers::TranslationFakeAdapter)
      expect(Providers::AdapterFactory.image_for(org: org)).to be_a(Providers::ImageGenerationFakeAdapter)
    end

    it "external được yêu cầu nhưng chưa có adapter thật → raise, không gọi mạng" do
      org.update!(ai_external_enabled: true)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TRANSLATION_PROVIDER").and_return("deepl")
      expect {
        Providers::AdapterFactory.translation_for(org: org)
      }.to raise_error(Providers::AdapterFactory::ExternalNotConfigured, /chưa được triển khai/)
    end
  end

  describe "ai_metadata không lưu raw prompt" do
    it "workflow lưu prompt_sha (hash), không lưu prompt gốc" do
      user = create(:user)
      create(:membership, organization: org, user: user, role: "strategist")
      campaign = create(:campaign, organization: org)
      artifact = Ai::Workflows::CampaignBrief.call(campaign: campaign, user: user)

      expect(artifact.ai_metadata["prompt"]).to be_nil
      expect(artifact.ai_metadata["prompt_sha"]).to match(/\A[0-9a-f]{64}\z/)
    end
  end
end
