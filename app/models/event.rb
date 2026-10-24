class Event < ApplicationRecord
  belongs_to :campaign
  has_many :event_attendees, dependent: :destroy
  has_many :attendees, through: :event_attendees, source: :user

  validates :title, presence: true
  validate :ends_after_starts

  def ends_after_starts
    errors.add(:ends_at, "phải sau thời gian bắt đầu") if ends_at <= starts_at
  end

  def to_ics
    attendee_lines = event_attendees.includes(:user).map do |a|
      "ATTENDEE;CN=#{a.user.name};RSVP=#{a.rsvp.upcase}:mailto:#{a.user.email}"
    end.join("\n")
    <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//MarketingOS//VN//EN
      BEGIN:VEVENT
      UID:event-#{id}@marketingos.local
      DTSTART:#{starts_at.utc.strftime("%Y%m%dT%H%M%SZ")}
      DTEND:#{ends_at.utc.strftime("%Y%m%dT%H%M%SZ")}
      SUMMARY:#{title}
      DESCRIPTION:#{agenda.to_s.gsub(/\n/, "\\n")}
      LOCATION:#{location.to_s}
      #{attendee_lines}
      END:VEVENT
      END:VCALENDAR
    ICS
  end

  def rsvp_for(user)
    event_attendees.find_by(user: user)
  end
end
