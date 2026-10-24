class AddAccessToCampaignCollaboratorToken < ActiveRecord::Migration[8.0]
  def change
    add_column :campaign_collaborator_tokens, :access, :string
  end
end
