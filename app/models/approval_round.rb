class ApprovalRound < ApplicationRecord
  STATUSES = %w[pending approved changes_requested rejected expired cancelled].freeze
  DECISIONS = %w[approved changes_requested rejected].freeze

  belongs_to :artifact
  belongs_to :requester, class_name: "User", optional: true
  has_many :approval_decisions, dependent: :destroy
  has_many :deciders, through: :approval_decisions, source: :user

  validates :status, inclusion: { in: STATUSES }
  validates :artifact_version, presence: true
  validate :reviewer_cannot_decide_twice, on: :create

  scope :active, -> { where(status: "pending") }
  scope :pending, -> { where(status: "pending") }

  # Ghi nhận MỘT decision của MỘT reviewer cho round này. Không ghi đè.
  def decide!(user:, decision:, note: nil)
    raise ActiveRecord::RecordInvalid, "round không còn mở" unless status == "pending"
    raise ArgumentError, "quyết định không hợp lệ" unless DECISIONS.include?(decision)

    approval_decisions.create!(user: user, decision: decision, note: note)
    recompute_status!
    self
  end

  # Status của round suy ra từ decisions:
  # - rejected/changes_requested là terminal, thắng mọi decision khác.
  # - approved khi: có quorum → đủ số lượt; không quorum → TẤT CẢ reviewer đã approve.
  def recompute_status!
    ds = approval_decisions.reload
    total_reviewers = Array(reviewer_ids).size
    new_status =
      if ds.any? { |d| d.decision == "rejected" }
        "rejected"
      elsif ds.any? { |d| d.decision == "changes_requested" }
        "changes_requested"
      elsif quorum.present?
        ds.count { |d| d.decision == "approved" } >= quorum ? "approved" : "pending"
      else
        (total_reviewers.positive? && ds.count { |d| d.decision == "approved" } >= total_reviewers) ? "approved" : "pending"
      end
    update!(status: new_status)
    sync_artifact_status
    self
  end

  # Artifact status chỉ phản chiếu round KHớP VERSION và là round mới nhất
  # chưa bị huỷ — quyết định trên version cũ không đánh dấu version mới.
  def sync_artifact_status
    return unless artifact
    return if status == "pending"
    # Round đã huỷ không đổi trạng thái artifact.
    return if status == "cancelled"

    latest = artifact.approval_rounds.where.not(status: "cancelled").order(id: :desc).first
    return unless latest&.id == id
    # Version phải còn là version hiện tại của artifact.
    return unless artifact_version == artifact.version

    mapping = { "approved" => "approved", "changes_requested" => "changes_requested",
                "rejected" => "rejected", "expired" => "in_review" }
    # Giữ transition hợp lệ theo state machine (dùng update! để validation chạy).
    artifact.update!(approval_status: mapping.fetch(status, "in_review"))
  rescue ActiveRecord::RecordInvalid
    # Artifact đã rời in_review (rút/edited) — bỏ sync, giữ nguyên trạng thái hiện tại.
    nil
  end

  private

  def reviewer_cannot_decide_twice
    # Validation ở decision level (unique index); đây là chặn sớm khi gọi decide! 2 lần.
  end
end
