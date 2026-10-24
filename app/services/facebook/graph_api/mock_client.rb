# frozen_string_literal: true

module Facebook
  module GraphApi
    # Client GIẢ — chỉ dùng ngoài production (FACEBOOK_MOCK_MODE=true) và trong
    # test. Mô phỏng các endpoint mà module dùng, trả ID có tiền tố "mock_" để
    # không bao giờ nhầm với bài thật. Không gọi mạng.
    #
    # Test có thể bơm lỗi: MockClient.instance.fail_next!(ApiError.new(...))
    # hoặc cắm `responses` tuỳ ý.
    class MockClient
      MOCK_PAGES = [
        { "id" => "100000000000001", "name" => "MarketFlow Demo Page", "category" => "Marketing Agency",
          "link" => "https://www.facebook.com/marketflow.demo", "username" => "marketflow.demo",
          "tasks" => %w[ANALYZE ADVERTISE MODERATE MESSAGING CREATE_CONTENT MANAGE],
          "picture" => { "data" => { "url" => "" } }, "access_token" => "mock_page_token_1" },
        { "id" => "100000000000002", "name" => "Cửa hàng Demo", "category" => "Retail Company",
          "link" => "https://www.facebook.com/cuahang.demo", "username" => "cuahang.demo",
          "tasks" => %w[ANALYZE MODERATE MESSAGING CREATE_CONTENT],
          "picture" => { "data" => { "url" => "" } }, "access_token" => "mock_page_token_2" }
      ].freeze

      attr_reader :calls, :published

      def self.instance = (@instance ||= new)
      def self.reset! = @instance = new

      def initialize
        @calls = []
        @published = []
        @queued_errors = []
      end

      def mock? = true

      def fail_next!(error) = @queued_errors << error

      def get(path, params = {})
        record(:get, path, params)
        raise_queued!
        case path
        when "/oauth/access_token", "oauth/access_token"
          { "access_token" => "mock_user_token_#{SecureRandom.hex(4)}", "token_type" => "bearer", "expires_in" => 5_183_944 }
        when "/me/accounts", "me/accounts"
          { "data" => MOCK_PAGES.map(&:dup), "paging" => {} }
        when "/debug_token", "debug_token"
          { "data" => { "is_valid" => true, "app_id" => "mock_app", "type" => "PAGE",
                        "scopes" => Facebook::Config::REQUIRED_SCOPES, "expires_at" => 0 } }
        when %r{\A/?(\d+)\z}
          page = MOCK_PAGES.find { |p| p["id"] == Regexp.last_match(1) }
          page ? page.slice("id", "name", "link", "category") : { "id" => Regexp.last_match(1), "name" => "Mock Page" }
        when %r{\A/?(\d+)_(\w+)\z}
          post_id = path.delete_prefix("/")
          { "id" => post_id, "permalink_url" => "https://www.facebook.com/#{post_id.sub('_', '/posts/')}",
            "created_time" => Time.current.iso8601 }
        when %r{\A/?\d+/feed\z}
          { "data" => @published.last(10).map { |p| p.slice("id", "message", "created_time") } }
        else
          {}
        end
      end

      def post(path, params = {})
        record(:post, path, params)
        raise_queued!
        page_id = path.delete_prefix("/").split("/").first
        case path
        when %r{/feed\z}
          id = "#{page_id}_mock#{SecureRandom.random_number(10**12)}"
          @published << { "id" => id, "message" => params[:message] || params["message"],
                          "created_time" => Time.current.iso8601 }
          { "id" => id }
        when %r{/photos\z}
          photo_id = "mock#{SecureRandom.random_number(10**12)}"
          post_id = "#{page_id}_#{photo_id}"
          @published << { "id" => post_id, "message" => params[:message] || params["message"],
                          "created_time" => Time.current.iso8601 }
          { "id" => photo_id, "post_id" => post_id }
        else
          { "success" => true }
        end
      end

      def post_multipart(path, params = {}, file:)
        post(path, params.merge(_file: file[:filename]))
      end

      private

      def record(method, path, params)
        @calls << { method: method, path: path, params: params.except(:access_token, "access_token", :appsecret_proof) }
      end

      def raise_queued!
        err = @queued_errors.shift
        raise err if err
      end
    end
  end
end
