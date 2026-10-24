class CampaignCollaboratorToken < ApplicationRecord
  # Lời mời reviewer/client CÓ PHẠM VI campaign — khác invitation workspace.
  belongs_to :organization
  belongs_to :campaign
  belongs_to :invited_by, class_name: "User", optional: true

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :access, inclusion: { in: CampaignCollaborator::ACCESS }, allow_nil: true

  before_validation :generate_token
  before_validation { self.access ||= "approve" }
  before_validation { self.organization ||= campaign&.organization }

  scope :active, -> { where(revoked_at: nil, accepted_at: nil).where(-> { arel_table[:expires_at] > Time.current }) }

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(24)
    self.expires_at ||= 7.days.from_now
  end

  def expired? = expires_at <= Time.current
  def revoked? = revoked_at.present?
  def accepted? = accepted_at.present?
  def usable? = !expired? && !revoked? && !accepted?
end
