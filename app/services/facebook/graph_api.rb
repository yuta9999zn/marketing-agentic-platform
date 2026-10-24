# frozen_string_literal: true

module Facebook
  # Factory cho client Graph API. Test có thể cắm client giả qua `with_client`.
  module GraphApi
    class << self
      def client
        return Thread.current[:facebook_graph_client] if Thread.current[:facebook_graph_client]
        return MockClient.instance if Facebook::Config.mock_mode?

        HttpClient.new
      end

      # Dùng trong test/console: chạy block với client chỉ định.
      def with_client(client)
        previous = Thread.current[:facebook_graph_client]
        Thread.current[:facebook_graph_client] = client
        yield
      ensure
        Thread.current[:facebook_graph_client] = previous
      end
    end
  end
end
