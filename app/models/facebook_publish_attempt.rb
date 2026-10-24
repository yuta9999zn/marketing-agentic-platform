class FacebookPublishAttempt < ApplicationRecord
  OUTCOMES = %w[started success transient_failure permanent_failure skipped].freeze

  belongs_to :facebook_post

  validates :attempt_number, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }

  scope :recent, -> { order(created_at: :desc) }

  def failure? = outcome.end_with?("failure")
end
