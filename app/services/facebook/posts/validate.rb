# frozen_string_literal: true

module Facebook
  module Posts
    # Kiểm tra trước khi gọi Graph API. Trả về mảng mã lỗi (rỗng = hợp lệ).
    # Mọi lỗi ở đây là VĨNH VIỄN cho tới khi người dùng sửa — không retry.
    class Validate
      def self.call(post) = new(post).call

      def initialize(post)
        @post = post
        @conn = post.facebook_page_connection
      end

      def call
        issues = []
        issues << :connection_disconnected if @conn.disconnected?
        issues << :connection_not_connected if !@conn.disconnected? && !@conn.connected?
        issues << :token_missing unless @conn.token_present?
        issues << :missing_scopes if @conn.granted_scopes.present? && @conn.missing_scopes.any?
        issues << :message_blank if @post.message.to_s.strip.blank?
        issues << :message_too_long if @post.message.to_s.length > FacebookPost::MAX_MESSAGE_LENGTH
        issues << :link_required if @post.post_type == "link" && @post.link.blank?
        issues.concat(image_issues) if @post.post_type == "photo"
        issues << :blocked_term if blocked_term_hit?
        issues << :unconfigured if @conn.connection_mode == "live" && !Facebook::Config.configured?
        issues.uniq
      end

      private

      def image_issues
        return [ :image_missing ] unless @post.image.attached?

        blob = @post.image.blob
        out = []
        out << :image_type_unsupported unless FacebookPost::IMAGE_CONTENT_TYPES.include?(blob.content_type)
        out << :image_too_large if blob.byte_size > FacebookPost::MAX_IMAGE_BYTES
        out
      end

      def blocked_term_hit?
        terms = @conn.blocked_terms_list
        return false if terms.empty?

        text = @post.message.to_s.downcase
        terms.any? { |t| text.include?(t.downcase) }
      end
    end
  end
end
