# Một Facebook Page đã kết nối với organization.
#
# Token Page lưu mã hoá (access_token_ciphertext). Thuộc tính này bị loại khỏi
# inspect/serialize; `access_token` chỉ được gọi từ tầng service khi gọi Graph API.
class FacebookPageConnection < ApplicationRecord
  STATUSES = %w[connected token_expired permission_missing error disconnected].freeze
  MODES = %w[live mock].freeze

  self.filter_attributes += [ :access_token_ciphertext ]

  belongs_to :organization
  belongs_to :connected_by, class_name: "User", optional: true
  has_many :facebook_posts, dependent: :destroy

  validates :page_id, :page_name, presence: true
  validates :page_id, uniqueness: { scope: :organization_id }
  validates :status, inclusion: { in: STATUSES }
  validates :connection_mode, inclusion: { in: MODES }

  scope :active, -> { where.not(status: "disconnected") }

  def access_token=(plain)
    @access_token = nil
    self.access_token_ciphertext = Facebook::TokenCipher.encrypt(plain)
  end

  # Chỉ gọi từ service layer. KHÔNG dùng trong view/log.
  def access_token
    return nil if access_token_ciphertext.blank?

    @access_token ||= Facebook::TokenCipher.decrypt(access_token_ciphertext)
  end

  def serializable_hash(options = nil)
    super((options || {}).merge(except: Array((options || {})[:except]) + [ :access_token_ciphertext ]))
  end

  def mock? = connection_mode == "mock"
  def disconnected? = status == "disconnected"
  def connected? = status == "connected"
  def token_present? = access_token_ciphertext.present?

  def missing_scopes = Facebook::Config::REQUIRED_SCOPES - Array(granted_scopes)
  def missing_page_tasks = Facebook::Config::REQUIRED_PAGE_TASKS - Array(page_tasks)

  # Có thể đăng ngay bây giờ không — gồm cả hai kill switch.
  def publishable?
    connected? && token_present? && !publishing_paused? &&
      !organization.facebook_publishing_paused? && Facebook::Config.publishing_enabled?
  end

  def blocked_reason
    return :disconnected if disconnected?
    return :status unless connected?
    return :deploy_kill_switch unless Facebook::Config.publishing_enabled?
    return :org_paused if organization.facebook_publishing_paused?
    return :page_paused if publishing_paused?

    nil
  end

  def blocked_terms_list
    blocked_terms.to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)
  end

  def permalink = page_link.presence || "https://www.facebook.com/#{page_id}"

  # Sau khi kết nối: nếu đã biết thiếu quyền thì phản ánh ngay vào status.
  def refresh_status_from_scopes!
    return if disconnected?

    if granted_scopes.present? && missing_scopes.any? || page_tasks.present? && missing_page_tasks.any?
      update!(status: "permission_missing", last_error_code: missing_scopes.any? ? "missing_scopes" : "missing_page_role")
    end
  end

  def disconnect!(user:)
    transaction do
      update!(status: "disconnected", disconnected_at: Time.current, access_token_ciphertext: nil,
              auto_publish_enabled: false)
      @access_token = nil
      facebook_posts.where(status: %w[scheduled approved pending_approval publishing]).find_each do |post|
        post.update_columns(status: "failed", error_kind: "permanent", last_error_code: "page_disconnected",
                            last_error: "Page đã ngắt kết nối trước khi đăng.", schedule_token: nil,
                            updated_at: Time.current)
      end
      AuditLog.record!(org: organization, user: user, action: "facebook.page.disconnected", subject: self,
                       details: { "page_id" => page_id })
    end
  end
end
