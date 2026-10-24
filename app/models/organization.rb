class Organization < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  has_many :prompt_templates, dependent: :destroy
  has_many :project_templates, dependent: :destroy
  has_many :milestones, through: :campaigns
  has_many :clients, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :ai_calls, dependent: :destroy
  has_many :facebook_page_connections, dependent: :destroy
  has_many :facebook_posts, dependent: :destroy
  has_many :facebook_authorizations, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/, message: "chỉ gồm a-z, 0-9 và dấu gạch ngang" }

  before_validation { self.slug = name.to_s.parameterize if slug.blank? }

  # external_reviewer: role restricted — mọi quyền đến từ CampaignCollaborator
  # của campaign được mời (xem Policy::ACCESS_CAP), không có quyền org-wide.
  ROLES = %w[owner admin manager strategist copywriter designer project_manager approver client external_reviewer].freeze

  def member_role(user)
    memberships.find_by(user: user)&.role
  end
end
