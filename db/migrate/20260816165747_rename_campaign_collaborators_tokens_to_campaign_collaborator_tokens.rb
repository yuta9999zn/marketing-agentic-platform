# Fix table name mismatch: model CampaignCollaboratorToken suy ra bảng
# campaign_collaborator_tokens nhưng migration cũ tạo campaign_collaborators_tokens.
# Rename an toàn — không drop, không mất dữ liệu.
class RenameCampaignCollaboratorsTokensToCampaignCollaboratorTokens < ActiveRecord::Migration[8.0]
  def change
    return unless table_exists?(:campaign_collaborators_tokens)

    rename_table :campaign_collaborators_tokens, :campaign_collaborator_tokens
    # Index unique trên token được tạo bằng `index: { unique: true }` — SQLite
    # tự mang index theo rename (tên index giữ cũ, chức năng unique không đổi).
  end
end
