require "rails_helper"

# Kiểm tra những thứ chỉ hỏng khi TRIỂN KHAI, không hỏng khi chạy dev.
RSpec.describe "Sẵn sàng triển khai" do
  describe "Gemfile" do
    it "không trỏ gem vào đường dẫn tuyệt đối của một máy cụ thể" do
      gemfile = Rails.root.join("Gemfile").read
      # Đường dẫn kiểu D:/... hoặc C:\... sẽ không tồn tại trên Linux/Docker.
      expect(gemfile).not_to match(/path:\s*["'][A-Za-z]:[\/\\]/)
    end

    it "harness được vendor vào repo và load được" do
      expect(Rails.root.join("vendor/gems/cdfl_harness/lib/cdfl_harness.rb")).to exist
      expect(Rails.root.join("vendor/gems/cdfl_harness/cdfl_harness.gemspec")).to exist
      expect(CDFLHarness::VERSION).to be_present
    end
  end

  describe "Dockerfile" do
    it "copy vendor/ giữ nguyên cấu trúc thư mục" do
      dockerfile = Rails.root.join("Dockerfile").read
      # `COPY vendor/* ./vendor/` làm mất một cấp thư mục → gem nằm sai chỗ.
      expect(dockerfile).to include("COPY vendor/ ./vendor/")
      expect(dockerfile).not_to include("COPY vendor/* ./vendor/")
    end
  end

  describe "seeds" do
    # Đây là bug đã thật sự xảy ra: db:prepare chạy seeds khi container khởi động
    # lần đầu; seeds gọi model thật; model chưa tải xong → seeds ném lỗi →
    # db:prepare thất bại → container không lên được.
    it "KHÔNG gọi model thật, và không ném lỗi khi AI chưa sẵn sàng" do
      allow(Ai::Workflows::CampaignBrief).to receive(:call)
        .and_raise(CDFLHarness::Errors::AdapterError, "model 'qwen2.5:7b' not found")
      allow(Ai::Workflows::ScriptDraft).to receive(:call)
        .and_raise(CDFLHarness::Errors::AdapterError, "model not found")

      with_env("AI_PROVIDER" => "ollama") do
        expect { load Rails.root.join("db/seeds.rb").to_s }.not_to raise_error
      end

      # Provider thật → bỏ qua hẳn, không cố gọi.
      expect(Ai::Workflows::CampaignBrief).not_to have_received(:call)
      expect(Artifact.where(ai_generated: true).count).to eq(0)
    end

    it "vẫn tạo dữ liệu nghiệp vụ khi bỏ qua phần AI" do
      with_env("AI_PROVIDER" => "ollama") do
        load Rails.root.join("db/seeds.rb").to_s
      end
      expect(Organization.find_by(slug: "nova-agency")).to be_present
      expect(Campaign.count).to be > 0
      expect(PromptTemplate.count).to be > 0
      expect(ProjectTemplate.count).to be > 0
    end
  end

  describe "cấu hình production" do
    it "chưa khai SMTP_HOST thì KHÔNG gửi mail thật" do
      # Bảo vệ khỏi việc triển khai lần đầu âm thầm gửi mail ra ngoài.
      production = Rails.root.join("config/environments/production.rb").read
      expect(production).to include('if ENV["SMTP_HOST"].present?')
      expect(production).to include("config.action_mailer.delivery_method = :test")
    end

    it "không hard-code example.com" do
      production = Rails.root.join("config/environments/production.rb").read
      expect(production).not_to match(/default_url_options\s*=\s*\{\s*host:\s*["']example\.com/)
    end
  end

  describe "docker-compose production" do
    let(:compose) { Rails.root.join("docker-compose.prod.yml").read }

    it "có worker chạy Solid Queue — thiếu nó thì job AI không ai xử lý" do
      expect(compose).to include("./bin/jobs")
      expect(compose).to match(/worker:/)
    end

    it "không đọc OLLAMA_HOST từ env file (tránh dính localhost của môi trường dev)" do
      expect(compose).to include("OLLAMA_REMOTE_HOST")
      expect(compose).not_to match(/OLLAMA_HOST:\s*\$\{OLLAMA_HOST/)
    end

    it "KHÔNG publish cổng Ollama ra ngoài" do
      # Endpoint Ollama không có xác thực — mở ra internet là cho người khác
      # dùng model của mình, và có thể đọc được prompt.
      # Lấy đúng khối service "  ollama:" (thụt 2 khoảng trắng) tới hết khối.
      section = compose[/^  ollama:\n(?:(?:    |\n).*\n)*/m].to_s
      expect(section).to include("expose:")
      expect(section).not_to match(/^\s{4}ports:/)
    end
  end
end
