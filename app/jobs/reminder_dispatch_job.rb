class ReminderDispatchJob < ApplicationJob
  queue_as :default

  # Idempotent: service lock + state check nên chạy lại không gửi trùng.
  def perform
    Reminders::DispatchDueService.call
  end
end
