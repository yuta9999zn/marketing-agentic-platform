# Trạng thái tạm giữa OAuth callback và bước chọn Page. Token (user + từng Page)
# mã hoá; bản ghi hết hạn sau 15 phút và bị xoá ngay khi chọn Page.
class FacebookAuthorization < ApplicationRecord
  TTL = 15.minutes

  self.filter_attributes += %i[user_token_ciphertext page_tokens_ciphertext]

  belongs_to :organization
  belongs_to :user

  validates :expires_at, presence: true

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  def self.public_page_attrs(page)
    { "id" => page["id"].to_s, "name" => page["name"], "category" => page["category"],
      "link" => page["link"], "username" => page["username"], "tasks" => Array(page["tasks"]),
      "picture_url" => page.dig("picture", "data", "url") }
  end

  def active? = consumed_at.nil? && expires_at > Time.current

  def user_token=(plain)
    self.user_token_ciphertext = Facebook::TokenCipher.encrypt(plain)
  end

  def page_tokens=(map)
    self.page_tokens_ciphertext = Facebook::TokenCipher.encrypt(map.to_json)
  end

  def page_token(page_id)
    return nil if page_tokens_ciphertext.blank?

    JSON.parse(Facebook::TokenCipher.decrypt(page_tokens_ciphertext))[page_id.to_s]
  end

  def serializable_hash(options = nil)
    super((options || {}).merge(except: Array((options || {})[:except]) + %i[user_token_ciphertext page_tokens_ciphertext]))
  end

  # Page khớp gợi ý link người dùng đã dán (nếu có đúng một).
  def hinted_page
    return nil if page_hint.blank?

    matches = pages.select { |p| Facebook::PageUrlParser.match?(p, page_hint) }
    matches.one? ? matches.first : nil
  end
end
