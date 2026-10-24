# frozen_string_literal: true

require "net/http"
require "openssl"

module Facebook
  module GraphApi
    # Client Graph API thật (Net::HTTP, không thêm gem). Mọi lời gọi đi qua đây.
    #
    # - Mọi request gắn appsecret_proof (HMAC-SHA256 của token với app secret)
    #   theo khuyến nghị của Meta.
    # - Log CHỈ ghi method + path + status + fbtrace_id — không ghi params,
    #   không ghi body (body có thể chứa token).
    # - Lỗi mạng/timeout → NetworkError (tạm thời). Lỗi API → ApiError đã phân loại.
    class HttpClient
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 60

      def mock? = false

      def get(path, params = {})
        uri = build_uri(path, with_proof(params))
        req = Net::HTTP::Get.new(uri)
        perform(uri, req, "GET", path)
      end

      def post(path, params = {})
        uri = build_uri(path, {})
        req = Net::HTTP::Post.new(uri)
        req.set_form_data(stringify(with_proof(params)))
        perform(uri, req, "POST", path)
      end

      # Upload file (ảnh) dạng multipart. `file` = { io:, filename:, content_type: }.
      def post_multipart(path, params = {}, file:)
        uri = build_uri(path, {})
        req = Net::HTTP::Post.new(uri)
        form = stringify(with_proof(params)).to_a
        form << [ "source", file[:io], { filename: file[:filename], content_type: file[:content_type] } ]
        req.set_form(form, "multipart/form-data")
        perform(uri, req, "POST(multipart)", path)
      end

      private

      def base_url = "#{Facebook::Config.graph_host}/#{Facebook::Config.graph_version}"

      def build_uri(path, params)
        uri = URI.parse("#{base_url}/#{path.to_s.delete_prefix('/')}")
        uri.query = URI.encode_www_form(stringify(params)) if params.present?
        uri
      end

      def stringify(params)
        params.compact.transform_keys(&:to_s).transform_values { |v| v.is_a?(String) ? v : v.to_s }
      end

      def with_proof(params)
        token = params[:access_token] || params["access_token"]
        secret = Facebook::Config.app_secret
        return params if token.blank? || secret.blank? || token.to_s.include?("|")

        params.merge(appsecret_proof: OpenSSL::HMAC.hexdigest("SHA256", secret, token.to_s))
      end

      def perform(uri, req, method, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        response = http.request(req)
        parse(response, method, path)
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
             SocketError, OpenSSL::SSL::SSLError, EOFError, IOError => e
        Rails.logger.warn("[facebook] #{method} #{safe_path(path)} network error: #{e.class}")
        raise Facebook::NetworkError, "Không kết nối được Graph API (#{e.class})"
      end

      def parse(response, method, path)
        body = response.body.to_s
        json = body.present? ? JSON.parse(body) : {}
        trace = json.is_a?(Hash) ? json.dig("error", "fbtrace_id") : nil
        Rails.logger.info("[facebook] #{method} #{safe_path(path)} -> #{response.code}#{trace ? " fbtrace=#{trace}" : ''}")

        if json.is_a?(Hash) && json["error"]
          err = json["error"]
          raise Facebook::ApiError.new(err["message"], code: err["code"], subcode: err["error_subcode"],
                                                       type: err["type"], http_status: response.code,
                                                       fbtrace_id: err["fbtrace_id"])
        end
        unless response.is_a?(Net::HTTPSuccess)
          raise Facebook::ApiError.new("HTTP #{response.code}", http_status: response.code)
        end

        json
      rescue JSON::ParserError
        raise Facebook::ApiError.new("Phản hồi không phải JSON", http_status: response.code)
      end

      # Không log ID bài/Page dài dòng cũng không sao, nhưng tuyệt đối không log query.
      def safe_path(path) = path.to_s.split("?").first
    end
  end
end
