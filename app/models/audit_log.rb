class AuditLog < ApplicationRecord
  belongs_to :organization
  belongs_to :user, optional: true

  validates :action, presence: true

  def self.record!(org:, user: nil, action:, subject: nil, details: {})
    create!(organization: org, user: user, action: action,
            subject_type: subject&.class&.name, subject_id: subject&.id, details: details)
  end
end
