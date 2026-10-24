class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  validates :kind, presence: true
end
