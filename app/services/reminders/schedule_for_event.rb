# frozen_string_literal: true

module Reminders
  # Nhắc sự kiện cho từng attendee theo tùy chọn cá nhân (lead time + kênh).
  # Gọi khi mời attendee hoặc RSVP; idempotent theo (event, user, starts_at, lead)
  # — đổi giờ họp hoặc đổi lead → key mới, key cũ bị hủy.
  class ScheduleForEvent
    def self.call(event, user)
      prefix = "event_upcoming:#{event.id}:#{user.id}:"
      lead = user.reminder_lead_minutes
      run_at = event.starts_at - lead.minutes
      key = "#{prefix}#{event.starts_at.to_i}:#{lead}"
      return Reminder.cancel_stale!(prefix: prefix, keep_key: "__none__") if event.starts_at.past?

      reminder = Reminder.schedule!(
        org: event.campaign.organization,
        user: user,
        kind: "event_upcoming",
        run_at: run_at,
        payload: { "event_id" => event.id, "title" => event.title,
                   "starts_at" => event.starts_at.iso8601, "campaign" => event.campaign.name },
        idempotency_key: key,
        channel: user.reminder_channel
      )
      Reminder.cancel_stale!(prefix: prefix, keep_key: key)
      reminder
    end

    def self.call_for_attendees(event)
      event.event_attendees.includes(:user).find_each { |a| call(event, a.user) }
    end
  end
end
