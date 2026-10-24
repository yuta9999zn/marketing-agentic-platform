class User < ApplicationRecord
  has_secure_password

  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  has_many :campaign_collaborators, dependent: :destroy
  has_many :shared_campaigns, through: :campaign_collaborators, source: :campaign
  has_many :notifications, dependent: :destroy
  has_many :approvals, dependent: :destroy
  has_many :comments, dependent: :destroy

  # Tùy chọn cá nhân — whitelist cứng, giá trị lạ không bao giờ vào DB.
  LOCALES = %w[vi en].freeze
  REMINDER_LEADS = [15, 30, 60, 180, 720, 1440, 2880].freeze # phút
  REMINDER_CHANNELS = %w[in_app email].freeze

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :locale, inclusion: { in: LOCALES }, allow_nil: true
  validates :reminder_lead_minutes, inclusion: { in: REMINDER_LEADS }
  validates :reminder_channel, inclusion: { in: REMINDER_CHANNELS }

  NORMAL_EMAILS = /\A[^@\s]+@(?!example\.test\z)[^@\s]+\z/

  def membership_in(org)
    memberships.find_by(organization: org)
  end

  def role_in(org)
    membership_in(org)&.role
  end
end
