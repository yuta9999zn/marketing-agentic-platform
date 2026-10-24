# frozen_string_literal: true

# Namespace của module Facebook Fanpage + các lớp lỗi dùng chung.
# (Zeitwerk: file này định nghĩa namespace `Facebook` và các hằng con.)

module Facebook
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class NotConnectedError < Error; end
  class StateError < Error; end

  class ValidationError < Error
    attr_reader :issues

    def initialize(issues)
      @issues = Array(issues)
      super(@issues.join("; "))
    end
  end

  # Lỗi mạng/timeout — luôn coi là tạm thời (retry có giới hạn).
  class NetworkError < Error
    def kind = :network
    def transient? = true
  end

  # Lỗi Graph API trả về. Phân loại theo code/subcode/HTTP status của Meta:
  # https://developers.facebook.com/docs/graph-api/guides/error-handling
  class ApiError < Error
    attr_reader :code, :subcode, :type, :http_status, :fbtrace_id, :api_message

    # Tạm thời: unknown(1), service(2), rate limit app(4)/user(17)/page(32)/
    # custom(613), temporarily blocked(368 chỉ khi subcode nói rõ là tạm).
    TRANSIENT_CODES = [ 1, 2, 4, 17, 32, 341, 613 ].freeze
    RATE_LIMIT_CODES = [ 4, 17, 32, 613 ].freeze
    TOKEN_CODES = [ 102, 190 ].freeze
    POLICY_CODES = [ 368 ].freeze
    # 10 = permission denied; 200-299 = thiếu quyền cụ thể.
    def self.permission_code?(code) = code == 10 || (200..299).cover?(code.to_i)

    def initialize(message, code: nil, subcode: nil, type: nil, http_status: nil, fbtrace_id: nil)
      @api_message = message.to_s
      @code = code&.to_i
      @subcode = subcode&.to_i
      @type = type
      @http_status = http_status&.to_i
      @fbtrace_id = fbtrace_id
      super(sanitized_message)
    end

    def kind
      return :token_expired if TOKEN_CODES.include?(code)
      return :permission if self.class.permission_code?(code)
      return :rate_limited if RATE_LIMIT_CODES.include?(code)
      return :policy if POLICY_CODES.include?(code)
      return :transient if TRANSIENT_CODES.include?(code) || (http_status && http_status >= 500)
      return :unsupported_media if code == 324 || api_message.match?(/image|photo|media/i) && code == 100
      return :validation if code == 100

      :permanent
    end

    def transient? = %i[rate_limited transient].include?(kind)

    # Không bao giờ để token lọt vào message (Meta thỉnh thoảng echo tham số).
    def sanitized_message
      "Graph API lỗi #{code}#{subcode ? "/#{subcode}" : ''} (#{type || 'error'}): #{api_message}"
        .gsub(/access_token=[^&\s]+/i, "access_token=[FILTERED]")
        .gsub(/EAA[0-9A-Za-z]{20,}/, "[FILTERED_TOKEN]")
        .truncate(500)
    end

    def to_h
      { code: code, subcode: subcode, type: type, http_status: http_status, fbtrace_id: fbtrace_id,
        kind: kind, message: sanitized_message }
    end
  end
end
