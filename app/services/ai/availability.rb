# frozen_string_literal: true

module Ai
  # Kiểm tra provider AI có thực sự dùng được không, để UI nói thật thay vì
  # để người dùng bấm nút rồi nhận lỗi. Kết quả cache ngắn (30 giây) — Ollama
  # có thể được bật/tắt bất cứ lúc nào nên không cache lâu.
  #
  # KHÔNG bao giờ raise: mọi lỗi mạng đều trả về trạng thái "không sẵn sàng".
  class Availability
    Status = Struct.new(:provider, :model, :ready, :detail, keyword_init: true) do
      def ready? = ready
      def fake? = provider == "fake"
      def local? = provider == "ollama"
    end

    CACHE_KEY = "ai:availability"
    CACHE_TTL = 30.seconds
    PROBE_TIMEOUT = 3 # giây — chỉ hỏi danh sách model, không sinh chữ

    def self.status(refresh: false)
      Rails.cache.delete(CACHE_KEY) if refresh
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { compute }
    end

    def self.compute
      provider = Gateway.provider_name
      case provider
      when "fake"
        Status.new(provider: provider, model: "fake-model", ready: true,
                   detail: :fake)
      when "ollama"
        probe_ollama
      else
        # anthropic/openai: sẵn sàng khi có API key; không gọi mạng để kiểm tra.
        key = ENV["#{provider.upcase}_API_KEY"].presence
        Status.new(provider: provider, model: nil, ready: key.present?,
                   detail: key.present? ? :ok : :missing_key)
      end
    end

    def self.probe_ollama
      model = Gateway.ollama_model
      host = ENV["OLLAMA_HOST"].presence || "http://localhost:11434"
      names = installed_models(host)

      return Status.new(provider: "ollama", model: model, ready: false, detail: :unreachable) if names.nil?

      # Ollama chấp nhận "qwen2.5:7b"; danh sách trả về cũng dạng name:tag.
      # So khớp cả trường hợp người dùng ghi thiếu tag (mặc định :latest).
      installed = names.include?(model) || names.include?("#{model}:latest") ||
                  names.any? { |n| n.split(":").first == model }
      Status.new(provider: "ollama", model: model, ready: installed,
                 detail: installed ? :ok : :model_missing)
    end

    # Trả mảng tên model, hoặc nil nếu không kết nối được.
    def self.installed_models(host)
      uri = URI.join(host, "/api/tags")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = PROBE_TIMEOUT
      http.read_timeout = PROBE_TIMEOUT
      resp = http.request(Net::HTTP::Get.new(uri.path))
      return nil unless resp.code.to_i == 200

      JSON.parse(resp.body).fetch("models", []).filter_map { |m| m["name"] }
    rescue StandardError
      nil
    end
  end
end
