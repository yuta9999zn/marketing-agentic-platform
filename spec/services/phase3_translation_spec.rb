require "rails_helper"

# Phase 3 — dịch bằng mô hình ngôn ngữ. Không gọi mạng: stub Ai::Gateway.
RSpec.describe "Dịch bằng mô hình ngôn ngữ" do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:client) { create(:client, organization: org) }
  let(:campaign) { create(:campaign, organization: org, client: client) }

  before { create(:membership, organization: org, user: user, role: "manager") }

  def with_ollama(&block) = with_env("AI_PROVIDER" => "ollama", "OLLAMA_MODEL" => nil, &block)

  # Giả lập tầng gateway để không chạm mạng, nhưng vẫn đi qua adapter thật.
  def stub_llm(output)
    fake = instance_double(Ai::Gateway)
    allow(fake).to receive(:generate_text).and_return(output)
    allow(Ai::Gateway).to receive(:new).and_return(fake)
    fake
  end

  describe "AdapterFactory chọn adapter" do
    it "provider fake → adapter offline deterministic" do
      adapter = Providers::AdapterFactory.translation_for(org: org, user: user)
      expect(adapter).to be_a(Providers::TranslationFakeAdapter)
    end

    it "provider ollama → adapter LLM, KHÔNG cần bật consent gửi ra ngoài" do
      with_ollama do
        expect(org.ai_external_enabled).to be false
        adapter = Providers::AdapterFactory.translation_for(org: org, user: user)
        expect(adapter).to be_a(Providers::TranslationLlmAdapter)
      end
    end

    it "yêu cầu provider ngoài chưa triển khai thì báo lỗi rõ, không âm thầm dùng fake" do
      org.update!(ai_external_enabled: true)
      with_env("AI_PROVIDER" => "fake", "TRANSLATION_PROVIDER" => "deepl") do
        expect { Providers::AdapterFactory.translation_for(org: org, user: user) }
          .to raise_error(Providers::AdapterFactory::ExternalNotConfigured, /deepl/)
      end
    end
  end

  describe "TranslationLlmAdapter" do
    it "bỏ câu dẫn thừa mà model hay thêm" do
      with_ollama do
        stub_llm("Here is the translation:\nThis summer ACME launches cold brew.")
        adapter = Providers::TranslationLlmAdapter.new(org: org, user: user)
        out = adapter.translate(text: "Mùa hè này ACME ra mắt cold brew.", source: "vi", target: "en")
        expect(out).to eq("This summer ACME launches cold brew.")
      end
    end

    it "bóc khối code khi model bọc kết quả trong ```" do
      with_ollama do
        stub_llm("```\nThis summer ACME launches cold brew.\n```")
        adapter = Providers::TranslationLlmAdapter.new(org: org, user: user)
        out = adapter.translate(text: "Mùa hè này...", source: "vi", target: "en")
        expect(out).to eq("This summer ACME launches cold brew.")
      end
    end

    it "prompt cấm model tự thêm hashtag/emoji và cấm bịa nội dung" do
      with_ollama do
        gw = stub_llm("ok")
        Providers::TranslationLlmAdapter.new(org: org, user: user)
                                        .translate(text: "xin chào", source: "vi", target: "en")
        expect(gw).to have_received(:generate_text) do |args|
          expect(args[:prompt]).to include("KHÔNG thêm bất cứ nội dung nào không có trong bản gốc")
          expect(args[:prompt]).to include("không thêm hashtag")
          expect(args[:task]).to eq("translation.vi.en")
        end
      end
    end

    it "cắt văn bản quá dài và nói rõ đã cắt" do
      with_ollama do
        stub_llm("translated")
        long = "a" * (Providers::TranslationLlmAdapter::MAX_INPUT_CHARS + 500)
        out = Providers::TranslationLlmAdapter.new(org: org, user: user)
                                              .translate(text: long, source: "vi", target: "en")
        expect(out).to include("chưa được dịch")
      end
    end

    it "đưa thuật ngữ bắt buộc vào prompt" do
      with_ollama do
        gw = stub_llm("ok")
        Providers::TranslationLlmAdapter.new(org: org, user: user)
                                        .translate(text: "cà phê", source: "vi", target: "en",
                                                   glossary: { "cà phê" => "coffee" })
        expect(gw).to have_received(:generate_text) do |args|
          expect(args[:prompt]).to include("cà phê → coffee")
        end
      end
    end
  end

  describe "Translations::CreateService" do
    it "ghi đúng model đang dùng vào audit" do
      source = campaign.artifacts.create!(kind: "social_post", title: "Bài gốc", body: "Nội dung")
      with_ollama do
        stub_llm("Translated content")
        artifact = Translations::CreateService.call(source_artifact: source, user: user, target_locale: "en")
        expect(artifact.body).to eq("Translated content")
        expect(artifact.approval_status).to eq("draft")
        expect(AiRun.last.model).to eq("qwen2.5:7b")
        expect(AiRun.last.provider).to eq("translation_ollama")
      end
    end
  end

  describe "Translations::QuickTranslate" do
    it "dịch mà KHÔNG tạo artifact, nhưng vẫn ghi audit" do
      with_ollama do
        stub_llm("Please add Q2 revenue figures.")
        expect {
          result = Translations::QuickTranslate.call(text: "Cần thêm số liệu quý 2.", org: org,
                                                     user: user, target_locale: "en")
          expect(result.text).to eq("Please add Q2 revenue figures.")
          expect(result.truncated).to be false
        }.to change(AiRun, :count).by(1).and change(Artifact, :count).by(0)
      end
    end

    it "từ chối chuỗi rỗng" do
      expect { Translations::QuickTranslate.call(text: "   ", org: org, user: user) }
        .to raise_error(ArgumentError)
    end

    it "cắt đoạn quá dài" do
      with_ollama do
        stub_llm("x")
        long = "b" * (Translations::QuickTranslate::MAX_CHARS + 10)
        expect(Translations::QuickTranslate.call(text: long, org: org, user: user).truncated).to be true
      end
    end
  end
end
