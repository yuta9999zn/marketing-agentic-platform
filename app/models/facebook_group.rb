# Một hội nhóm Facebook trong danh bạ của workspace (nhập tay).
#
# Không có kết nối API: Meta đã gỡ Groups API năm 2024. Bản ghi chỉ phục vụ
# lên kế hoạch + nhắc người dùng tự chia sẻ bài vào nhóm.
class FacebookGroup < ApplicationRecord
  URL_PATTERN = %r{\Ahttps://(www\.|m\.|web\.)?facebook\.com/groups/[^/?#\s]+/?\z}i

  belongs_to :organization
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :default_assignee, class_name: "User", optional: true
  has_many :facebook_group_shares, dependent: :restrict_with_error

  before_validation :normalize_url
  before_validation :normalize_tags

  validates :name, presence: true, length: { maximum: 200 }
  validates :url, presence: true, uniqueness: { scope: :organization_id }
  validate :url_is_facebook_group
  validate :assignee_in_same_organization

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  def tag_list = tags.to_s.split(",").map(&:strip).reject(&:blank?)

  def self.all_tags(org) = where(organization: org).pluck(:tags).flat_map { |t| t.to_s.split(",").map(&:strip) }.reject(&:blank?).uniq.sort

  # Thống kê nhanh cho danh sách nhóm.
  def share_counts = facebook_group_shares.group(:status).count

  private

  # Chuẩn hoá về https://www.facebook.com/groups/<slug>, bỏ query (?ref=share...).
  def normalize_url
    return if url.blank?

    raw = url.strip
    raw = "https://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
    uri = URI.parse(raw)
    return unless uri.host.to_s.match?(/(\A|\.)facebook\.com\z/i)

    slug = uri.path.to_s.split("/").reject(&:blank?)
    return unless slug.first&.casecmp?("groups") && slug[1].present?

    self.url = "https://www.facebook.com/groups/#{slug[1]}"
  rescue URI::InvalidURIError
    nil # để validate báo lỗi
  end

  def normalize_tags
    self.tags = tag_list.uniq.join(", ").presence if tags_changed?
  end

  def url_is_facebook_group
    return if url.blank? || url.match?(URL_PATTERN)

    errors.add(:url, :invalid_group_url)
  end

  def assignee_in_same_organization
    return if default_assignee.nil? || organization.nil?
    return if FacebookGroupShare.assignable_users(organization).exists?(id: default_assignee_id)

    errors.add(:default_assignee, :invalid)
  end
end
