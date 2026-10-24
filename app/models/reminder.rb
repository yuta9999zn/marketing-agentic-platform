class Reminder < ApplicationRecord
  STATES = %w[queued sent failed cancelled].freeze

  belongs_to :organization
  belongs_to :user

  validates :state, inclusion: { in: STATES }
  validates :kind, :run_at, :idempotency_key, presence: true

  scope :due, -> { where(state: "queued").where(run_at: ..Time.current) }

  def self.schedule!(org:, user:, kind:, run_at:, payload: {}, idempotency_key: nil, channel: "in_app")
    key = idempotency_key || "#{kind}:#{user.id}:#{run_at.to_i}"
    find_or_create_by!(idempotency_key: key) do |r|
      r.organization = org
      r.user = user
      r.kind = kind
      r.run_at = run_at
      r.payload = payload
      r.channel = channel
    end
  end

  # Hủy các reminder queued cùng tiền tố key nhưng khác key hiện hành — dùng khi
  # hạn/lead time đổi: key mới được tạo, key cũ không còn đúng thì thôi gửi.
  #
  # Prefix chứa dấu "_" (vd "task_due_soon:") nên phải escape để "_" không thành
  # ký tự đại diện; ESCAPE '\' là bắt buộc, thiếu nó SQLite/Postgres hiểu dấu
  # backslash theo nghĩa đen và truy vấn không khớp gì.
  def self.cancel_stale!(prefix:, keep_key:)
    where(state: "queued")
      .where("idempotency_key LIKE ? ESCAPE '\\'", "#{sanitize_sql_like(prefix)}%")
      .where.not(idempotency_key: keep_key)
      .find_each(&:cancel!)
  end

  def mark_sent! = update!(state: "sent")
  def mark_failed! = update!(state: "failed")
  def cancel! = update!(state: "cancelled")
end
