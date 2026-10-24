require "rails_helper"

# Phase 1 — nhắc nhở theo cấu hình cá nhân (lead time + kênh) cho task và event.
RSpec.describe "Nhắc nhở theo cấu hình người dùng" do
  let(:org) { create(:organization) }
  let(:user) { create(:user, reminder_lead_minutes: 60, reminder_channel: "in_app") }
  let!(:membership) { create(:membership, organization: org, user: user, role: "manager") }
  let(:client) { create(:client, organization: org) }
  let(:campaign) { create(:campaign, organization: org, client: client) }

  describe "task" do
    it "đặt lịch nhắc theo lead time của người được giao" do
      task = campaign.tasks.create!(title: "Viết bài", assignee: user, due_date: Date.new(2026, 9, 10))
      Reminders::ScheduleForTask.call(task)

      reminder = Reminder.last
      expect(reminder.user).to eq(user)
      expect(reminder.channel).to eq("in_app")
      # Mốc hạn 09:00 ngày 10/9, nhắc trước 60 phút → 08:00.
      expect(reminder.run_at.in_time_zone).to eq(Time.zone.local(2026, 9, 10, 8, 0))
    end

    it "đổi lead time thì hủy lịch cũ và tạo lịch mới, không gửi trùng" do
      task = campaign.tasks.create!(title: "Viết bài", assignee: user, due_date: Date.new(2026, 9, 10))
      Reminders::ScheduleForTask.call(task)
      old = Reminder.last

      user.update!(reminder_lead_minutes: 1440)
      Reminders::ScheduleForTask.call(task)

      expect(old.reload.state).to eq("cancelled")
      queued = Reminder.where(state: "queued")
      expect(queued.count).to eq(1)
      expect(queued.first.run_at.in_time_zone).to eq(Time.zone.local(2026, 9, 9, 9, 0))
    end

    it "chạy lại nhiều lần không tạo bản ghi trùng" do
      task = campaign.tasks.create!(title: "Viết bài", assignee: user, due_date: Date.new(2026, 9, 10))
      3.times { Reminders::ScheduleForTask.call(task) }
      expect(Reminder.where(state: "queued").count).to eq(1)
    end

    it "task hoàn thành thì hủy lịch nhắc đang chờ" do
      task = campaign.tasks.create!(title: "Viết bài", assignee: user, due_date: Date.new(2026, 9, 10))
      Reminders::ScheduleForTask.call(task)

      task.update!(status: "done")
      Reminders::ScheduleForTask.call(task)
      expect(Reminder.where(state: "queued").count).to eq(0)
    end
  end

  describe "event" do
    it "đặt lịch nhắc cho người tham dự theo lead time riêng của họ" do
      other = create(:user, reminder_lead_minutes: 1440)
      create(:membership, organization: org, user: other, role: "copywriter")
      event = create(:event, campaign: campaign, starts_at: Time.zone.local(2026, 9, 20, 14, 0),
                             ends_at: Time.zone.local(2026, 9, 20, 15, 0))

      Reminders::ScheduleForEvent.call(event, user)
      Reminders::ScheduleForEvent.call(event, other)

      expect(Reminder.find_by(user: user).run_at.in_time_zone).to eq(Time.zone.local(2026, 9, 20, 13, 0))
      expect(Reminder.find_by(user: other).run_at.in_time_zone).to eq(Time.zone.local(2026, 9, 19, 14, 0))
    end

    it "không đặt lịch cho sự kiện đã qua" do
      event = create(:event, campaign: campaign, starts_at: 2.days.ago, ends_at: 2.days.ago + 1.hour)
      Reminders::ScheduleForEvent.call(event, user)
      expect(Reminder.count).to eq(0)
    end
  end

  describe "dispatch" do
    it "kênh in_app chỉ tạo notification, không gửi mail" do
      user.update!(reminder_channel: "in_app")
      Reminder.schedule!(org: org, user: user, kind: "task_due_soon", run_at: 1.minute.ago,
                         payload: { "title" => "Task A" }, idempotency_key: "k1", channel: "in_app")

      expect {
        expect(Reminders::DispatchDueService.call).to eq(1)
      }.to change(Notification, :count).by(1)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "kênh email tạo notification VÀ gửi mail giao dịch" do
      Reminder.schedule!(org: org, user: user, kind: "task_due_soon", run_at: 1.minute.ago,
                         payload: { "title" => "Task B" }, idempotency_key: "k2", channel: "email")

      perform_enqueued_jobs do
        expect(Reminders::DispatchDueService.call).to eq(1)
      end
      expect(Notification.count).to eq(1)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
    end

    it "chạy lại không gửi trùng" do
      Reminder.schedule!(org: org, user: user, kind: "task_due_soon", run_at: 1.minute.ago,
                         payload: {}, idempotency_key: "k3")
      expect(Reminders::DispatchDueService.call).to eq(1)
      expect(Reminders::DispatchDueService.call).to eq(0)
    end
  end

  describe "resync sau khi đổi cài đặt" do
    it "dựng lại lịch nhắc cho task và event còn hiệu lực của chính user" do
      task = campaign.tasks.create!(title: "Viết bài", assignee: user, due_date: 10.days.from_now.to_date)
      Reminders::ScheduleForTask.call(task)
      event = create(:event, campaign: campaign, starts_at: 5.days.from_now, ends_at: 5.days.from_now + 1.hour)
      event.event_attendees.create!(user: user)
      Reminders::ScheduleForEvent.call(event, user)

      user.update!(reminder_lead_minutes: 2880)
      Reminders::Resync.call(user: user, org: org)

      queued = Reminder.where(state: "queued")
      expect(queued.count).to eq(2)
      expect(queued.map(&:kind)).to match_array(%w[task_due_soon event_upcoming])
    end

    it "không đụng tới lịch nhắc của người khác" do
      other = create(:user)
      create(:membership, organization: org, user: other, role: "copywriter")
      other_task = campaign.tasks.create!(title: "Task người khác", assignee: other,
                                          due_date: 10.days.from_now.to_date)
      Reminders::ScheduleForTask.call(other_task)
      before_run_at = Reminder.find_by(user: other).run_at

      user.update!(reminder_lead_minutes: 15)
      Reminders::Resync.call(user: user, org: org)

      expect(Reminder.find_by(user: other).run_at).to eq(before_run_at)
      expect(Reminder.find_by(user: other).state).to eq("queued")
    end
  end
end
