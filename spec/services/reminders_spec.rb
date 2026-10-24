require "rails_helper"

RSpec.describe Reminders::DispatchDueService do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }

  it "schedule! idempotent theo idempotency key" do
    expect {
      2.times { Reminder.schedule!(org: org, user: user, kind: "task_due_soon", run_at: 1.hour.from_now, idempotency_key: "k1") }
    }.to change(Reminder, :count).by(1)
  end

  it "dispatch reminder đến hạn: tạo notification, đánh dấu sent, không gửi lại" do
    Reminder.schedule!(org: org, user: user, kind: "task_due_soon",
                       run_at: 1.minute.ago, payload: { "task" => "X" }, idempotency_key: "due1")
    Reminder.schedule!(org: org, user: user, kind: "task_due_soon",
                       run_at: 1.day.from_now, idempotency_key: "future1")

    expect(described_class.call).to eq(1)
    expect(Notification.where(user: user, kind: "task_due_soon").count).to eq(1)
    expect(Reminder.find_by(idempotency_key: "due1").state).to eq("sent")
    expect(Reminder.find_by(idempotency_key: "future1").state).to eq("queued")

    # Chạy lại — không gửi trùng.
    expect(described_class.call).to eq(0)
    expect(Notification.where(user: user, kind: "task_due_soon").count).to eq(1)
  end
end
