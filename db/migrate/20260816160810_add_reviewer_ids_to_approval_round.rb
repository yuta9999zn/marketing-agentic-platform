class AddReviewerIdsToApprovalRound < ActiveRecord::Migration[8.0]
  def change
    add_column :approval_rounds, :reviewer_ids, :json
  end
end
