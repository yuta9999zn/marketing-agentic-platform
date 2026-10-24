require "rails_helper"

# Phase 3 — nối provider chạy trên máy (Ollama). KHÔNG gọi mạng: mọi ví dụ đều
# stub ENV hoặc tầng HTTP.
RSpec.describe "Gateway với provider chạy trên máy" do
  describe "Ai::Gateway phân loại provider" do
    it "mặc định là fake và chạy đồng bộ" do
      expect(Ai::Gateway.provider_name).to eq("fake")
      expect(Ai::Gateway.fake_provider?).to be true
      expect(Ai::Gateway.local_provider?).to be false
      expect(Ai::Gateway.synchronous?).to be true
    end

    it "ollama là local, KHÔNG đồng bộ (phải chạy nền)" do
      with_provider("ollama") do
        expect(Ai::Gateway.local_provider?).to be true
        expect(Ai::Gateway.fake_provider?).to be false
        expect(Ai::Gateway.synchronous?).to be false
      end
    end

    it "lấy model từ ENV, không phụ thuộc mặc định của harness" do
      with_provider("ollama") do
        expect(Ai::Gateway.ollama_model).to eq("qwen2.5:7b")
      end
      with_env("AI_PROVIDER" => "ollama", "OLLAMA_MODEL" => "llama3.2:1b") do
        expect(Ai::Gateway.ollama_model).to eq("llama3.2:1b")
      end
    end

    it "ollama KHÔNG bật cờ external — dữ liệu không rời khỏi máy" do
      org = create(:organization)
      org.update!(ai_external_enabled: true)
      with_provider("ollama") do
        cfg = Ai::Gateway.new(org: org).config
        expect(cfg.provider).to eq(:ollama)
        expect(cfg.external?).to be false
        expect(cfg.external_enabled).to be false
        expect(cfg.default_model).to eq("qwen2.5:7b")
      end
    end

    it "không tiêm fake completion khi provider là ollama" do
      org = create(:organization)
      with_provider("ollama") do
        gw = Ai::Gateway.new(org: org, fake_completion: ->(_p) { "{}" })
        expect(gw.config.adapter_override).to be_nil
        expect(gw.provider_label).to eq("ollama")
      end
    end
  end

  describe "Ai::Availability" do
    before { Rails.cache.clear }

    it "provider fake luôn sẵn sàng" do
      st = Ai::Availability.status(refresh: true)
      expect(st).to be_ready
      expect(st.fake?).to be true
    end

    it "báo không sẵn sàng khi không gọi được Ollama — không raise" do
      with_provider("ollama") do
        allow(Ai::Availability).to receive(:installed_models).and_return(nil)
        st = Ai::Availability.status(refresh: true)
        expect(st).not_to be_ready
        expect(st.detail).to eq(:unreachable)
      end
    end

    it "báo thiếu model khi Ollama chạy nhưng chưa tải model" do
      with_provider("ollama") do
        allow(Ai::Availability).to receive(:installed_models).and_return(["llama3.2:1b"])
        st = Ai::Availability.status(refresh: true)
        expect(st).not_to be_ready
        expect(st.detail).to eq(:model_missing)
      end
    end

    it "sẵn sàng khi model đã có (khớp cả khi thiếu tag)" do
      with_provider("ollama") do
        allow(Ai::Availability).to receive(:installed_models).and_return(["qwen2.5:7b", "bge-m3:latest"])
        expect(Ai::Availability.status(refresh: true)).to be_ready
      end
    end
  end

  # ENV thật của máy chạy test có thể khác — luôn set tường minh.
  def with_provider(name, &block)
    with_env("AI_PROVIDER" => name, "OLLAMA_MODEL" => nil, "OLLAMA_HOST" => nil, &block)
  end
end
