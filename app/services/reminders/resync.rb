# frozen_string_literal: true

module Reminders
  # Dựng lại lịch nhắc của MỘT user sau khi họ đổi lead time / kênh nhắc.
  # Chỉ đụng đến task/event của chính user trong org hiện tại — reminder theo
  # key cũ bị hủy bên trong ScheduleFor*, nên chạy lại nhiều lần vẫn an toàn.
  class Resync
    def self.call(user:, org:)
      campaign_ids = Campaign.where(organization: org).select(:id)

      Task.where(campaign_id: campaign_ids, assignee: user)
          .where.not(status: "done").where.not(due_date: nil)
          .find_each { |task| ScheduleForTask.call(task) }

      Event.joins(:event_attendees)
           .where(campaign_id: campaign_ids, event_attendees: { user_id: user.id })
           .where(starts_at: Time.current..)
           .find_each { |event| ScheduleForEvent.call(event, user) }
    end
  end
end
