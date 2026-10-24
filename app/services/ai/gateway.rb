# frozen_string_literal: true

module Ai
  # Server-managed chokepoint around CDFLHarness::Gateway::Client.
  # - Mặc định chạy Fake adapter (không mạng) bất kể ENV, trừ khi AI_PROVIDER được cấu hình.
  # - Provider ngoài phải vượt double-gate: AI_EXTERNAL_ENABLED=true (master switch)
  #   VÀ consent_external=true cho từng lần gọi (K-4 của harness — không consent thì
  #   router tự downgrade về local).
  # - Audit sink ghi vào bảng ai_calls: chỉ SHA-256 hash của prompt/output, không lưu raw.
  class Gateway
    class ConsentRequiredError < StandardError; end

    attr_reader :config, :client

    # Provider hiện tại có phải fake không — workflows chỉ inject scripted
    # completion khi đúng, để provider thật (đã gate đầy đủ) được dùng.
    def self.fake_provider? = provider_name == "fake"

    # Ollama chạy trên máy: harness coi là INTERNAL (external? == false) nên
    # không cần consent gate — dữ liệu khách hàng không rời khỏi máy.
    def self.local_provider? = provider_name == "ollama"

    def self.provider_name = (ENV["AI_PROVIDER"].presence || "fake").to_s

    # Model dùng cho Ollama. Harness mặc định qwen2.5:14b — máy có thể chưa tải,
    # nên luôn lấy từ ENV để cấu hình được mà không sửa code.
    def self.ollama_model = ENV["OLLAMA_MODEL"].presence || "qwen2.5:7b"

    # Provider có đủ nhanh để chạy ngay trong request web không?
    # Fake trả kết quả tức thì. Model thật mất 20-90 giây (nạp model + sinh chữ)
    # nên phải đẩy sang job nền, nếu không người dùng ngồi nhìn trang treo.
    def self.synchronous? = fake_provider?

    def initialize(org: nil, user: nil, fake_completion: nil)
      @org = org
      @user = user
      @config = build_config
      if fake_completion && self.class.fake_provider?
        # Chế độ offline có kiểm soát: scripted completion cho demo/test.
        @config.adapter_override = CDFLHarness::Gateway::Adapters::Fake.new(
          completions: [fake_completion]
        )
      end
      audit = CDFLHarness::Gateway::Middleware::Audit.new(sink: method(:write_audit_row))
      @config.middleware = [CDFLHarness::Gateway::Middleware::PII.new, audit]
      @client = CDFLHarness::Gateway::Client.new(config: @config)
    end

    def generate_structured(prompt:, task:, schema:, consent_external: false, max_tokens: 2000)
      if consent_external && !@config.external_enabled
        raise ConsentRequiredError,
              "Provider ngoài chưa được bật (AI_EXTERNAL_ENABLED). Hỏi admin workspace trước khi gửi dữ liệu ra ngoài."
      end
      @client.complete_structured(prompt: prompt, task: task, schema: schema,
                                  consent_external: consent_external, max_tokens: max_tokens)
    end

    # Sinh văn bản tự do (không ràng buộc JSON schema). Dùng cho dịch thuật và
    # các tác vụ mà model nhỏ khó trả JSON hợp lệ — tránh vòng repair không cần thiết.
    def generate_text(prompt:, task:, consent_external: false, max_tokens: 2000)
      if consent_external && !@config.external_enabled
        raise ConsentRequiredError,
              "Provider ngoài chưa được bật (AI_EXTERNAL_ENABLED). Hỏi admin workspace trước khi gửi dữ liệu ra ngoài."
      end
      @client.complete(prompt: prompt, task: task,
                       consent_external: consent_external, max_tokens: max_tokens)
    end

    def model_label = @config.default_model || @config.model_for

    def provider_label
      if @config.adapter_override
        "fake"
      else
        @config.provider.to_s
      end
    end

    private

    def build_config
      cfg = CDFLHarness::Config.new
      cfg.provider = self.class.provider_name.to_sym
      # Triple-gate: ENV master switch VÀ org setting (owner/admin bật) VÀ consent từng call.
      cfg.external_enabled = ENV["AI_EXTERNAL_ENABLED"] == "true" &&
                             cfg.provider != :fake &&
                             (@org.nil? || @org.ai_external_enabled?)
      cfg.api_keys = {
        anthropic: ENV["ANTHROPIC_API_KEY"],
        openai: ENV["OPENAI_API_KEY"]
      }
      cfg.ollama_host = ENV["OLLAMA_HOST"] if ENV["OLLAMA_HOST"].present?
      # Model của harness mặc định là qwen2.5:14b; máy này có thể tải bản khác,
      # nên ghim theo ENV để không phụ thuộc mặc định của gem.
      cfg.default_model = self.class.ollama_model if cfg.provider == :ollama
      cfg
    end

    def write_audit_row(row)
      return unless @org

      AiCall.create!(
        organization: @org,
        user: @user,
        task: row[:task],
        model: row[:model].to_s,
        method: row[:method].to_s,
        prompt_sha: row[:prompt_sha],
        output_sha: row[:output_sha],
        repaired: row[:repaired] || false,
        latency_ms: row[:latency_ms]
      )
    rescue StandardError
      # Audit best-effort — không làm hỏng lời gọi AI.
    end
  end
end
