# frozen_string_literal: true

module Reminders
  # Dispatch reminder đến hạn. Idempotent nhờ state machine + unique idempotency_key.
  # Local chỉ tạo in-app notification + log — không gửi mail thật.
  class DispatchDueService
    def self.call(now: Time.current)
      dispatched = 0
      Reminder.due.find_each do |r|
        r.with_lock do
          next unless r.state == "queued" && r.run_at <= now
          begin
            Notification.create!(user: r.user, organization: r.organization,
                                 kind: r.kind, payload: r.payload)
            # Kênh email: enqueue mail giao dịch — dev là :test adapter (không gửi
            # thật), production cần SMTP. In-app notification luôn được tạo.
            ReminderMailer.reminder(r).deliver_later if r.channel == "email"
            r.mark_sent!
            dispatched += 1
          rescue StandardError => e
            r.update!(state: "failed", payload: r.payload.merge("error" => e.class.name))
          end
        end
      end
      dispatched
    end
  end
end
