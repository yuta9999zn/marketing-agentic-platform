class CampaignCollaborator < ApplicationRecord
  # approve = reviewer ngoài được duyệt artifact CỦA CAMPAIGN ĐƯỢC MỜI.
  ACCESS = %w[view comment approve].freeze

  belongs_to :campaign
  belongs_to :user

  validates :access, inclusion: { in: ACCESS }
  validates :user_id, uniqueness: { scope: :campaign_id }
end
