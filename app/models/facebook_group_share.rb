# Một lượt chia sẻ: bài Page đã đăng × một hội nhóm, do người dùng tự đăng.
#
#   pending → posted | rejected | skipped     (mở lại: → pending)
#
# Hệ thống không bao giờ tự đăng vào nhóm; nó chỉ nhắc đúng giờ (Reminder) và
# lưu kết quả người dùng đánh dấu.
class FacebookGroupShare < ApplicationRecord
  STATUSES = %w[pending posted rejected skipped].freeze
  DONE_STATUSES = %w[posted rejected skipped].freeze
  REMINDER_KIND = "facebook_group_share_due"

  belongs_to :organization
  belongs_to :facebook_post
  belongs_to :facebook_group
  belongs_to :assignee, class_name: "User"
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :completed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :scheduled_at, presence: true
  validates :facebook_group_id, uniqueness: { scope: :facebook_post_id }
  validates :message, length: { maximum: FacebookPost::MAX_MESSAGE_LENGTH }
  validate :group_post_url_is_facebook, if: -> { group_post_url.present? }
  validate :same_organization

  scope :in_org, ->(org) { where(organization: org) }
  scope :pending, -> { where(status: "pending") }
  scope :done, -> { where(status: DONE_STATUSES) }
  scope :due, ->(now = Time.current) { pending.where(scheduled_at: ..now) }
  scope :chronological, -> { order(:scheduled_at, :id) }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # Chỉ thành viên nội bộ mới được giao việc đăng nhóm (không giao cho client).
  def self.assignable_users(org)
    org.users.where(memberships: { role: Authentication::INTERNAL_ROLES }).distinct.order(:name)
  end

  def done? = DONE_STATUSES.include?(status)
  def overdue?(now = Time.current) = pending? && scheduled_at < now - 15.minutes

  # Nội dung để dán vào nhóm: biến thể riêng nếu có, không thì nội dung bài Page.
  def text_to_post = message.presence || facebook_post.message

  def page_link = facebook_post.permalink_url

  def timezone = facebook_post.timezone
  def scheduled_local = scheduled_at.in_time_zone(timezone)

  def reminder_key_prefix = "fb_group_share:#{id}:"
  def reminder_key = "#{reminder_key_prefix}#{scheduled_at.to_i}:#{assignee_id}"

  private

  def group_post_url_is_facebook
    uri = URI.parse(group_post_url.strip)
    ok = uri.is_a?(URI::HTTP) && uri.host.to_s.match?(/(\A|\.)(facebook\.com|fb\.com|fb\.me)\z/i)
    errors.add(:group_post_url, :invalid) unless ok
  rescue URI::InvalidURIError
    errors.add(:group_post_url, :invalid)
  end

  def same_organization
    return if organization_id.nil?

    errors.add(:facebook_post, :invalid) if facebook_post && facebook_post.organization_id != organization_id
    errors.add(:facebook_group, :invalid) if facebook_group && facebook_group.organization_id != organization_id
    errors.add(:assignee, :invalid) if assignee && !self.class.assignable_users(organization).exists?(id: assignee_id)
  end
end
