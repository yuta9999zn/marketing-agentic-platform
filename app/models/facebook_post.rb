# Bài đăng Facebook Page. State machine:
#   draft → pending_approval → approved → scheduled → publishing → published
#                                   ↘ failed (retry → scheduled) ; cancelled
# Không có đường tắt nào từ draft/pending_approval sang publishing: mọi bài đều
# phải qua approved (người duyệt, hoặc auto-publish được bật rõ ràng).
class FacebookPost < ApplicationRecord
  STATUSES = %w[draft pending_approval approved scheduled publishing published failed cancelled].freeze
  POST_TYPES = %w[text photo link].freeze
  MAX_MESSAGE_LENGTH = 63_206
  IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp image/bmp].freeze
  MAX_IMAGE_BYTES = 4.megabytes
  CONTENT_ATTRS = %w[message link post_type].freeze

  TRANSITIONS = {
    "draft" => %w[pending_approval cancelled],
    "pending_approval" => %w[approved draft cancelled],
    "approved" => %w[scheduled publishing draft cancelled],
    "scheduled" => %w[publishing approved draft cancelled],
    "publishing" => %w[published failed scheduled],
    "failed" => %w[scheduled draft cancelled],
    "published" => [],
    "cancelled" => %w[draft]
  }.freeze

  belongs_to :organization
  belongs_to :facebook_page_connection
  belongs_to :campaign, optional: true
  belongs_to :artifact, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :facebook_publish_attempts, dependent: :destroy
  has_many :facebook_group_shares, dependent: :destroy
  has_one_attached :image

  validates :status, inclusion: { in: STATUSES }
  validates :post_type, inclusion: { in: POST_TYPES }
  validates :message, presence: true, length: { maximum: MAX_MESSAGE_LENGTH }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :timezone, presence: true
  validate :timezone_known
  validate :link_is_http, if: -> { link.present? }
  validate :transition_allowed, on: :update, if: :status_changed?
  validate :campaign_in_same_organization

  before_validation { self.idempotency_key ||= SecureRandom.uuid }

  scope :in_org, ->(org) { where(organization: org) }
  scope :awaiting_approval, -> { where(status: "pending_approval") }
  scope :upcoming, -> { where(status: "scheduled").order(:scheduled_at) }
  scope :due, -> { where(status: "scheduled").where("COALESCE(next_attempt_at, scheduled_at) <= ?", Time.current) }
  scope :recent_activity, -> { where(status: %w[published failed]).order(Arel.sql("COALESCE(published_at, updated_at) DESC")) }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  def connection = facebook_page_connection

  def can_transition_to?(new_status) = TRANSITIONS.fetch(status, []).include?(new_status)

  def editable? = %w[draft pending_approval approved failed scheduled].include?(status)
  def approvable? = pending_approval?
  def schedulable? = %w[approved scheduled].include?(status)
  def cancellable? = %w[draft pending_approval approved scheduled failed].include?(status)
  def retryable? = failed?
  def retrying? = scheduled? && attempts.positive? && next_attempt_at.present?
  def terminal? = published? || cancelled?
  def needs_manual_check? = failed? && last_error_code == "publish_state_unknown"

  def scheduled_local = scheduled_at&.in_time_zone(timezone)

  def effective_run_at = next_attempt_at || scheduled_at || Time.current

  def hashtags = Array(ai_metadata["hashtags"])
  def call_to_action = ai_metadata["call_to_action"]
  def image_suggestions = Array(ai_metadata["image_suggestions"])

  def content_fingerprint = Digest::SHA256.hexdigest([ message, link, post_type ].join("\u0000"))

  # Tạo token lịch mới: job cũ (đang chờ wait_until) sẽ thấy token lệch và bỏ qua.
  def rotate_schedule_token! = self.schedule_token = SecureRandom.hex(12)

  private

  def timezone_known
    errors.add(:timezone, "không hợp lệ") if timezone.present? && ActiveSupport::TimeZone[timezone].nil?
  end

  def link_is_http
    uri = URI.parse(link)
    errors.add(:link, "phải là http(s)") unless uri.is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    errors.add(:link, "không hợp lệ")
  end

  def transition_allowed
    return if status_was.nil? || status_was == status
    return if TRANSITIONS.fetch(status_was, []).include?(status)

    errors.add(:status, "không thể chuyển từ #{status_was} sang #{status}")
  end

  def campaign_in_same_organization
    errors.add(:campaign, "phải thuộc cùng organization") if campaign && campaign.organization_id != organization_id
  end
end
