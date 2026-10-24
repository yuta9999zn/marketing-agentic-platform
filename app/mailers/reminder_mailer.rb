class ReminderMailer < ApplicationMailer
  # Email nhắc nhở (task đến hạn / sự kiện sắp diễn ra). Dev: delivery_method
  # :test — không gửi thật; production cần SMTP/Resend (Phase 2).
  def reminder(reminder)
    @reminder = reminder
    @title = reminder.payload["title"].to_s
    subject =
      case reminder.kind
      when "event_upcoming" then "[MarketingOS] Sắp diễn ra: #{@title}"
      else "[MarketingOS] Sắp đến hạn: #{@title}"
      end
    mail to: reminder.user.email, subject: subject
  end
end
