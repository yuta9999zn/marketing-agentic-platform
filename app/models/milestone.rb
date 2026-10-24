class Milestone < ApplicationRecord
  STATES = %w[not_started in_progress blocked ready_for_review completed].freeze

  belongs_to :campaign
  belongs_to :owner, class_name: "User", optional: true
  has_many :tasks, dependent: :nullify

  validates :title, presence: true
  validates :state, inclusion: { in: STATES }

  scope :ordered, -> { order(:position, :id) }

  # Trạng thái milestone suy ra từ tasks thật khi có task; ngược lại giữ state thủ công.
  def effective_state
    return state if tasks.empty?

    t = tasks
    return "completed" if t.where.not(status: "done").empty?
    return "blocked" if t.where.not(blocked_reason: nil).exists?

    "in_progress"
  end
end
