class Approval < ApplicationRecord
  # Legacy record (pre-round). Luồng mới dùng ApprovalRound/ApprovalDecision —
  # KHÔNG còn ghi đè artifact status từ đây để tôn trọng state machine.
  DECISIONS = %w[approved rejected changes_requested].freeze

  belongs_to :artifact
  belongs_to :user
  belongs_to :approval_round, optional: true

  validates :decision, inclusion: { in: DECISIONS }
end
