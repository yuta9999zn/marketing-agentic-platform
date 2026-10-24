require "rails_helper"

RSpec.describe "Facebook group sharing (manual)" do
  include ActiveJob::TestHelper

  let(:org) { create(:organization) }
  let(:owner) { create(:user, name: "Chủ") }
  let(:writer) { create(:user, name: "Biên tập", reminder_channel: "email") }
  let(:client_user) { create(:user) }
  let!(:m1) { create(:membership, organization: org, user: owner, role: "owner") }
  let!(:m2) { create(:membership, organization: org, user: writer, role: "copywriter") }
  let!(:m3) { create(:membership, organization: org, user: client_user, role: "client") }
  let(:conn) { create(:facebook_page_connection, organization: org) }
  let(:post) { create(:facebook_post, :published, organization: org, facebook_page_connection: conn, message: "Căn hộ 2PN Cầu Giấy, 68m2, giá 4,2 tỷ. LH 0909 000 111") }
  let!(:g1) { create(:facebook_group, organization: org, name: "Mua bán căn hộ Cầu Giấy") }
  let!(:g2) { create(:facebook_group, organization: org, name: "Nhà đất Hà Nội", allows_links: false, rules_note: "Cấm link") }
  let!(:g3) { create(:facebook_group, organization: org, name: "Cho thuê", default_assignee: writer) }

  def plan(**opts)
    Facebook::GroupShares::Plan.call(post: post, user: owner, group_ids: [ g1.id, g2.id, g3.id ],
                                     start_at: 1.hour.from_now.in_time_zone(post.timezone).strftime("%Y-%m-%dT%H:%M"), **opts)
  end

  describe Facebook::GroupShares::Plan do
    it "tạo một lượt mỗi nhóm, giãn cách đều, người phụ trách theo mặc định của nhóm" do
      result = plan(spacing_minutes: 30)
      shares = result.created
      expect(shares.size).to eq(3)
      expect(shares.map(&:facebook_group)).to eq([ g1, g2, g3 ])
      expect(shares.each_cons(2).map { |a, b| (b.scheduled_at - a.scheduled_at).to_i }).to eq([ 1800, 1800 ])
      expect(shares.map(&:assignee)).to eq([ owner, owner, writer ])
      expect(shares).to all(be_pending)
      expect(AuditLog.where(action: "facebook.group_share.planned").count).to eq(1)
    end

    it "người phụ trách chọn trong form ghi đè mặc định; client không được giao" do
      shares = plan(assignee_id: writer.id).created
      expect(shares.map(&:assignee).uniq).to eq([ writer ])
      expect { Facebook::GroupShares::Plan.call(post: create(:facebook_post, :published, organization: org, facebook_page_connection: conn), user: owner,
                                                group_ids: [ g1.id ], start_at: nil, assignee_id: client_user.id) }
        .to raise_error(ArgumentError)
    end

    it "lên lời nhắc đúng giờ theo kênh của người phụ trách và đặt job chạy đúng giờ" do
      shares = nil
      expect { shares = plan.created }.to have_enqueued_job(ReminderDispatchJob).exactly(3).times
      reminders = Reminder.where(kind: FacebookGroupShare::REMINDER_KIND).order(:run_at)
      expect(reminders.map(&:run_at)).to eq(shares.map(&:scheduled_at))
      expect(reminders.map(&:channel)).to eq(%w[in_app in_app email])
      expect(reminders.first.payload).to include("group" => g1.name)
    end

    it "không tạo trùng nhóm đã có trong kế hoạch của bài" do
      plan
      again = plan
      expect(again.created).to be_empty
      expect(again.skipped_existing.size).to eq(3)
      expect(post.facebook_group_shares.count).to eq(3)
    end

    it "chỉ bài đã đăng; không nhận giờ quá khứ, giãn cách lạ, nhóm của org khác hoặc nhóm đã ẩn" do
      draft = create(:facebook_post, organization: org, facebook_page_connection: conn)
      expect { Facebook::GroupShares::Plan.call(post: draft, user: owner, group_ids: [ g1.id ], start_at: nil) }
        .to raise_error(Facebook::StateError)
      expect { Facebook::GroupShares::Plan.call(post: post, user: owner, group_ids: [ g1.id ], start_at: "2020-01-01T09:00") }
        .to raise_error(ArgumentError)
      expect { Facebook::GroupShares::Plan.call(post: post, user: owner, group_ids: [ g1.id ], start_at: nil, spacing_minutes: 7) }
        .to raise_error(ArgumentError)
      foreign = create(:facebook_group)
      g1.update!(active: false)
      other_post = create(:facebook_post, :published, organization: org, facebook_page_connection: conn)
      expect { Facebook::GroupShares::Plan.call(post: other_post, user: owner, group_ids: [ foreign.id, g1.id ], start_at: nil) }
        .to raise_error(ArgumentError)
    end
  end

  describe Facebook::GroupShares::Transitions do
    let(:share) { plan.created.first }

    it "đánh dấu đã đăng: lưu link bài trong nhóm, huỷ lời nhắc, ghi audit; không đánh dấu hai lần" do
      Facebook::GroupShares::Transitions.complete(share, user: writer, status: "posted",
                                                         group_post_url: "https://www.facebook.com/groups/abc/posts/123")
      share.reload
      expect(share).to be_posted
      expect(share.completed_by).to eq(writer)
      expect(share.group_post_url).to eq("https://www.facebook.com/groups/abc/posts/123")
      expect(Reminder.where("idempotency_key LIKE ?", "fb_group_share:#{share.id}:%").pluck(:state)).to all(eq("cancelled"))
      expect(AuditLog.where(action: "facebook.group_share.posted", subject_id: share.id)).to exist
      expect { Facebook::GroupShares::Transitions.complete(share, user: writer, status: "skipped") }
        .to raise_error(Facebook::StateError)
    end

    it "từ chối link bài không phải Facebook và trạng thái lạ" do
      expect { Facebook::GroupShares::Transitions.complete(share, user: owner, status: "posted", group_post_url: "https://evil.example/x") }
        .to raise_error(ActiveRecord::RecordInvalid)
      expect { Facebook::GroupShares::Transitions.complete(share, user: owner, status: "pending") }
        .to raise_error(ArgumentError)
      expect(share.reload).to be_pending
    end

    it "admin từ chối rồi mở lại → về chờ đăng" do
      Facebook::GroupShares::Transitions.complete(share, user: owner, status: "rejected", note: "Admin không duyệt")
      expect(share.reload).to be_rejected
      expect(share.note).to eq("Admin không duyệt")
      expect(share.group_post_url).to be_nil
      Facebook::GroupShares::Transitions.reopen(share, user: owner)
      expect(share.reload).to be_pending
      expect(share.completed_at).to be_nil
    end

    it "đổi giờ: lời nhắc cũ bị huỷ, lời nhắc mới đúng giờ mới" do
      new_time = 3.hours.from_now.in_time_zone(share.timezone).change(sec: 0)
      Facebook::GroupShares::Transitions.update(share, user: owner, scheduled_at: new_time.strftime("%Y-%m-%dT%H:%M"))
      queued = Reminder.where("idempotency_key LIKE ?", "fb_group_share:#{share.id}:%").where(state: "queued")
      expect(queued.count).to eq(1)
      expect(queued.first.run_at).to eq(new_time)
    end

    it "sửa nội dung tay thì bỏ nhãn AI; xoá khỏi kế hoạch huỷ lời nhắc" do
      share.update!(message: "Bản AI", ai_variant: true)
      Facebook::GroupShares::Transitions.update(share, user: owner, message: "Bản tôi tự sửa")
      expect(share.reload.message).to eq("Bản tôi tự sửa")
      expect(share.ai_variant).to be false
      id = share.id
      Facebook::GroupShares::Transitions.remove(share, user: owner)
      expect(FacebookGroupShare.exists?(id)).to be false
      expect(Reminder.where("idempotency_key LIKE ?", "fb_group_share:#{id}:%").where(state: "queued")).to be_empty
    end
  end

  it "đến giờ: lời nhắc tạo thông báo trong app và email (theo kênh) cho người phụ trách" do
    shares = plan.created
    Reminder.where(kind: FacebookGroupShare::REMINDER_KIND).update_all(run_at: 1.minute.ago)
    expect { Reminders::DispatchDueService.call }.to change { Notification.where(kind: "facebook_group_share_due").count }.by(3)
    expect(Notification.where(kind: "facebook_group_share_due").pluck(:user_id).sort).to eq(shares.map(&:assignee_id).sort)
    mail = enqueued_jobs.select { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" }
    expect(mail.size).to eq(1) # chỉ writer chọn kênh email
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)
    delivered = ActionMailer::Base.deliveries.last
    expect(delivered.subject).to include(g3.name)
    expect(delivered.body.encoded).to include("Cho thu")
  end

  it "AI (fake) viết mỗi nhóm một bản: giữ dữ kiện, nhóm cấm link không có URL" do
    shares = plan.created
    updated = Ai::Workflows::FacebookGroupVariants.call(shares: shares, user: owner)
    expect(updated.size).to eq(3)
    texts = shares.map { |s| s.reload.message }
    expect(texts.uniq.size).to eq(3)
    expect(texts).to all(include("4,2 tỷ"))
    expect(shares.map(&:ai_variant)).to all(be true)
    no_link = shares.find { |s| s.facebook_group == g2 }
    expect(no_link.message).not_to match(%r{https?://})
    expect(shares.find { |s| s.facebook_group == g1 }.message).to include(post.permalink_url)
    expect(AiRun.where(workflow: "facebook_group_variants")).to exist
  end
end
