class Membership < ApplicationRecord
  belongs_to :organization
  belongs_to :user

  validates :role, inclusion: { in: Organization::ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }
end
