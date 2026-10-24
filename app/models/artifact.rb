class Artifact < ApplicationRecord
  KINDS = %w[brief persona content_plan social_post video_script event_run_of_show email
             landing_page ad_copy storyboard image_prompt report deliverable translation].freeze

  # State machine chuẩn: draft → in_review → (approved | changes_requested | rejected) → archived.
  # Nội dung đã duyệt chỉ nằm ở artifact_versions — edit luôn tạo version mới, không overwrite.
  APPROVAL_STATUSES = %w[draft in_review approved changes_requested rejected archived].freeze
  TRANSITIONS = {
    "draft" => %w[in_review archived],
    "in_review" => %w[approved changes_requested rejected cancelled_to_draft archived],
    "approved" => %w[archived],
    "changes_requested" => %w[in_review archived],
    "rejected" => %w[in_review archived],
    "archived" => []
  }.freeze

  belongs_to :campaign
  belongs_to :created_by, class_name: "User", optional: true
  has_many :artifact_versions, dependent: :destroy
  has_many :approvals, dependent: :destroy
  has_many :approval_rounds, dependent: :destroy
  has_many :comments, dependent: :destroy
  # Audit AI trỏ về artifact qua khoá ngoại. Xoá artifact thì GIỮ dòng audit
  # (chỉ bỏ con trỏ) — audit không được biến mất. Thiếu dòng này, xoá campaign
  # hoặc khách hàng có nội dung do AI tạo sẽ vi phạm khoá ngoại và lỗi 500.
  has_many :ai_runs, foreign_key: :output_artifact_id, dependent: :nullify, inverse_of: :output_artifact

  validates :kind, inclusion: { in: KINDS }
  validates :title, presence: true
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validate :transition_allowed, on: :update, if: :approval_status_changed?

  scope :templates, -> { where(template: true) }
  scope :in_review, -> { where(approval_status: "in_review") }

  after_create :snapshot_version

  def ai_label
    ai_generated ? (ai_metadata["edited_by_human"] ? "AI-assisted" : "AI-generated") : nil
  end

  def can_transition_to?(new_status)
    TRANSITIONS.fetch(approval_status, []).include?(new_status) ||
      # "cancelled_to_draft" là đường về draft khi rút lại bản chờ duyệt
      (new_status == "draft" && approval_status == "in_review" && false)
  end

  def transition!(new_status)
    raise ArgumentError, "Không thể chuyển từ #{approval_status} sang #{new_status}" unless can_transition_to?(new_status)

    real = new_status == "cancelled_to_draft" ? "draft" : new_status
    update!(approval_status: real)
  end

  # Rút lại bản đang chờ duyệt về draft (hủy round đang mở).
  def withdraw!
    raise ArgumentError, "chỉ rút được bản in_review" unless approval_status == "in_review"

    approval_rounds.pending.update_all(status: "cancelled")
    update!(approval_status: "draft")
  end

  def new_version!(body, ai_generated:, ai_metadata: {}, user: nil, extra: {})
    latest = artifact_versions.maximum(:version) || 0
    transaction do
      # Sửa artifact đang in_review → atomically HỦY mọi round pending của
      # version cũ (stale) rồi đưa về draft. Không cho round cũ sống sót.
      if approval_status == "in_review"
        approval_rounds.where(status: "pending").update_all(status: "cancelled")
      end
      # Trạng thái chuyển về draft khi có chỉnh sửa mới (trừ archived).
      new_status = approval_status == "archived" ? "archived" : "draft"
      update!(body: body, version: latest + 1, ai_generated: ai_generated,
              ai_metadata: ai_metadata, approval_status: new_status,
              created_by: user || created_by, **extra)
      snapshot_version
    end
    self
  end

  # Restore một version cũ = tạo version MỚI mang nội dung đó — không đụng history.
  def restore_version!(version_number, user: nil)
    v = artifact_versions.find_by!(version: version_number)
    new_version!(v.body, ai_generated: v.ai_generated,
                 ai_metadata: v.ai_metadata.merge("restored_from_version" => version_number), user: user)
  end

  # Duplicate trong cùng campaign.
  def duplicate!(user: nil)
    campaign.artifacts.create!(
      kind: kind, title: "#{title} (bản sao)", body: body, ai_generated: ai_generated,
      ai_metadata: ai_metadata.merge("duplicated_from_id" => id), created_by: user || created_by,
      locale: locale, channel: channel, due_date: due_date, source_note: source_note
    )
  end

  private

  def snapshot_version
    artifact_versions.create!(body: body, version: version, ai_generated: ai_generated,
                              ai_metadata: ai_metadata, created_by: created_by)
  end

  def transition_allowed
    return true if approval_status_was.nil? # record mới
    return true if approval_status_was == approval_status
    return true if TRANSITIONS.fetch(approval_status_was, []).include?(approval_status)
    # Chỉnh sửa nội dung đưa về draft được phép từ mọi trạng thái chưa archive.
    return true if approval_status == "draft" && %w[in_review changes_requested rejected approved].include?(approval_status_was)

    errors.add(:approval_status, "không thể chuyển từ #{approval_status_was} sang #{approval_status}")
  end
end
