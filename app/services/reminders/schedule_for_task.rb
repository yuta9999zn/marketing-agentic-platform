# frozen_string_literal: true

module Reminders
  # Task có assignee + due_date → reminder trước hạn theo tùy chọn của assignee
  # (reminder_lead_minutes, reminder_channel — cấu hình ở /settings).
  # Idempotent theo key gồm due_date + lead: đổi hạn hoặc đổi lead → key mới,
  # reminder theo key cũ bị hủy (cancel_stale!) nên không gửi trùng.
  class ScheduleForTask
    KEY_PREFIX = "task_due_soon"

    def self.call(task)
      prefix = "#{KEY_PREFIX}:#{task.id}:"
      if task.assignee.nil? || task.due_date.nil? || task.done?
        Reminder.cancel_stale!(prefix: prefix, keep_key: "__none__")
        return
      end

      lead = task.assignee.reminder_lead_minutes
      # Hạn task là ngày — mốc nhắc tính từ 09:00 sáng ngày hạn theo timezone workspace.
      due_moment = task.due_date.in_time_zone.change(hour: 9)
      key = "#{prefix}#{task.due_date}:#{lead}"

      reminder = Reminder.schedule!(
        org: task.campaign.organization,
        user: task.assignee,
        kind: "task_due_soon",
        run_at: due_moment - lead.minutes,
        payload: { "task_id" => task.id, "title" => task.title },
        idempotency_key: key,
        channel: task.assignee.reminder_channel
      )
      Reminder.cancel_stale!(prefix: prefix, keep_key: key)
      reminder
    end
  end
end
