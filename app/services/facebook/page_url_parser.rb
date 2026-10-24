# frozen_string_literal: true

module Facebook
  # Người dùng chỉ cần dán link Fanpage. Parser rút ra ID số hoặc username để
  # tự chọn đúng Page sau khi OAuth trả về danh sách Page họ quản lý.
  #
  # Chấp nhận: https://www.facebook.com/MyPage, facebook.com/MyPage/, fb.com/x,
  # m.facebook.com/x, https://www.facebook.com/profile.php?id=123,
  # https://www.facebook.com/pages/Ten/123456, "123456", "MyPage", "@MyPage".
  class PageUrlParser
    Result = Struct.new(:id, :username, :raw, keyword_init: true) do
      def present? = id.present? || username.present?
      def label = id || username
    end

    IGNORED_SEGMENTS = %w[pages people pg profile.php home.php groups events photos videos about].freeze

    def self.call(input)
      raw = input.to_s.strip
      return Result.new(raw: raw) if raw.blank?

      return Result.new(id: raw, raw: raw) if raw.match?(/\A\d{5,}\z/)
      return Result.new(username: raw.delete_prefix("@"), raw: raw) if raw.match?(/\A@?[A-Za-z0-9.\-_]+\z/) && !raw.include?(".com")

      uri = URI.parse(raw.match?(%r{\Ahttps?://}) ? raw : "https://#{raw}")
      return Result.new(raw: raw) unless uri.host.to_s.match?(/(\A|\.)(facebook\.com|fb\.com|fb\.me)\z/i)

      query = URI.decode_www_form(uri.query.to_s).to_h
      return Result.new(id: query["id"], raw: raw) if query["id"].to_s.match?(/\A\d+\z/)

      segments = uri.path.to_s.split("/").reject(&:blank?)
      # /pages/Name/123456 → id ở cuối
      if segments.first == "pages"
        id = segments.find { |s| s.match?(/\A\d{5,}\z/) }
        return Result.new(id: id, raw: raw) if id
      end
      candidate = segments.reject { |s| IGNORED_SEGMENTS.include?(s.downcase) }.first
      return Result.new(raw: raw) if candidate.blank?
      return Result.new(id: candidate, raw: raw) if candidate.match?(/\A\d{5,}\z/)

      Result.new(username: candidate.sub(/-\d+\z/, ""), raw: raw)
    rescue URI::InvalidURIError
      Result.new(raw: raw)
    end

    # Page (hash từ /me/accounts) có khớp gợi ý không.
    def self.match?(page, hint)
      res = hint.is_a?(Result) ? hint : call(hint)
      return false unless res.present?
      return true if res.id.present? && page["id"].to_s == res.id

      if res.username.present?
        uname = res.username.downcase
        return true if page["username"].to_s.downcase == uname
        link_slug = page["link"].to_s.split("/").reject(&:blank?).last.to_s.downcase
        return true if link_slug == uname || link_slug.sub(/-\d+\z/, "") == uname
      end
      false
    end
  end
end
