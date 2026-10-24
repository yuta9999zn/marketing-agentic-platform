class ApprovalDecision < ApplicationRecord
  belongs_to :approval_round
  belongs_to :user

  validates :decision, inclusion: { in: ApprovalRound::DECISIONS }
  # Một reviewer chỉ có một decision cho một round — DB unique index chống race.
  validates :user_id, uniqueness: { scope: :approval_round_id }
end
