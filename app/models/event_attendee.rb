class EventAttendee < ApplicationRecord
  RSVP = %w[invited yes no maybe].freeze

  belongs_to :event
  belongs_to :user

  validates :rsvp, inclusion: { in: RSVP }
  validates :user_id, uniqueness: { scope: :event_id }
end
