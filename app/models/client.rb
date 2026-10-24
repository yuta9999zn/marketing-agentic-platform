class Client < ApplicationRecord
  belongs_to :organization
  has_many :campaigns, dependent: :destroy

  validates :name, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :in_org, ->(org) { where(organization: org) }

  def active_campaigns = campaigns.where.not(status: %w[archived delivered])
end
