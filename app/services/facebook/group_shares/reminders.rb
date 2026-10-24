# frozen_string_literal: true

module Facebook
  module GroupShares
    # Nhắc người phụ trách đúng giờ chia sẻ vào nhóm.
    #
    # Dùng lại hạ tầng Reminder (in-app/email theo cài đặt từng người, idempotent
    # theo key). Ngoài sweeper định kỳ (production 30 phút/lần) còn đặt một
    # ReminderDispatchJob chạy ĐÚNG giờ hẹn, vì các nhóm chỉ cách nhau ~30 phút.
    module Reminders
      module_function

      def schedule(share)
        prefix = share.reminder_key_prefix
        unless share.pending?
          ::Reminder.cancel_stale!(prefix: prefix, keep_key: "__none__")
          return nil
        end

        key = share.reminder_key
        ::Reminder.cancel_stale!(prefix: prefix, keep_key: key)
        reminder = ::Reminder.schedule!(
          org: share.organization, user: share.assignee, kind: FacebookGroupShare::REMINDER_KIND,
          run_at: share.scheduled_at, idempotency_key: key, channel: share.assignee.reminder_channel,
          payload: { "group" => share.facebook_group.name,
                     "title" => share.facebook_post.title.presence || share.facebook_post.message.to_s.truncate(60),
                     "at" => I18n.l(share.scheduled_local, format: :datetime_short) }
        )
        ReminderDispatchJob.set(wait_until: [ share.scheduled_at, Time.current ].max).perform_later if reminder.state == "queued"
        reminder
      end

      def cancel(share)
        ::Reminder.cancel_stale!(prefix: share.reminder_key_prefix, keep_key: "__none__")
      end
    end
  end
end
