class Comment < ApplicationRecord
  belongs_to :campaign
  belongs_to :artifact, optional: true
  belongs_to :user

  validates :body, presence: true
  # Comment theo artifact phải thuộc đúng campaign của chính comment đó.
  validate :artifact_belongs_to_campaign

  private

  def artifact_belongs_to_campaign
    return if artifact.nil? || campaign.nil? || artifact.campaign_id == campaign_id

    errors.add(:artifact, "phải thuộc cùng campaign")
  end
end
