require "rails_helper"

RSpec.describe Facebook::Posts::Transitions do
  include ActiveJob::TestHelper

  let(:org) { create(:organization) }
  let(:author) { create(:user) }
  let(:approver) { create(:user) }
  let!(:m1) { create(:membership, organization: org, user: author, role: "copywriter") }
  let!(:m2) { create(:membership, organization: org, user: approver, role: "approver") }
  let(:conn) { create(:facebook_page_connection, organization: org) }
  let(:post) { create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: author) }

  it "draft → pending_approval → approved, ghi audit và thông báo approver" do
    described_class.submit(post, user: author)
    expect(post.reload.status).to eq("pending_approval")
    expect(Notification.where(kind: "facebook_post_pending_approval", user: approver)).to exist
    described_class.approve(post, user: approver)
    expect(post.reload.status).to eq("approved")
    expect(post.approved_by).to eq(approver)
    expect(post.approval_source).to eq("human")
    expect(AuditLog.pluck(:action)).to include("facebook.post.submitted", "facebook.post.approved")
  end

  it "duyệt bài đã có giờ đăng → tự lên lịch + enqueue job đúng giờ" do
    post.update!(scheduled_at: 2.hours.from_now)
    described_class.submit(post, user: author)
    expect { described_class.approve(post, user: approver) }.to have_enqueued_job(FacebookPublishJob).at(post.reload.scheduled_at)
    expect(post.status).to eq("scheduled")
  end

  it "không approve được bài draft (phải qua submit)" do
    expect { described_class.approve(post, user: approver) }.to raise_error(Facebook::StateError)
  end

  it "từ chối → draft kèm lý do + thông báo tác giả" do
    described_class.submit(post, user: author)
    described_class.reject(post, user: approver, note: "Thiếu CTA")
    expect(post.reload.status).to eq("draft")
    expect(post.rejection_note).to eq("Thiếu CTA")
    expect(Notification.where(kind: "facebook_post_rejected", user: author)).to exist
  end

  it "lên lịch: giờ địa phương theo timezone → UTC đúng" do
    described_class.submit(post, user: author)
    described_class.approve(post, user: approver)
    described_class.schedule(post, user: author, at: "2026-12-01T09:00", timezone: "Asia/Ho_Chi_Minh")
    expect(post.reload.scheduled_at.utc).to eq(Time.utc(2026, 12, 1, 2, 0))
    expect(post.scheduled_local.strftime("%H:%M %Z")).to eq("09:00 +07")
    described_class.schedule(post, user: author, at: "2026-12-01T09:00", timezone: "America/New_York")
    expect(post.reload.scheduled_at.utc).to eq(Time.utc(2026, 12, 1, 14, 0))
  end

  it "từ chối lịch trong quá khứ và múi giờ lạ" do
    described_class.submit(post, user: author)
    described_class.approve(post, user: approver)
    expect { described_class.schedule(post, user: author, at: 1.day.ago, timezone: "UTC") }.to raise_error(ArgumentError)
    expect { described_class.schedule(post, user: author, at: 1.day.from_now, timezone: "Mars/Olympus") }.to raise_error(ArgumentError)
  end

  it "đổi lịch xoay schedule_token → job cũ vô hiệu" do
    described_class.submit(post, user: author)
    described_class.approve(post, user: approver)
    described_class.schedule(post, user: author, at: 1.day.from_now, timezone: "UTC")
    old = post.reload.schedule_token
    described_class.schedule(post, user: author, at: 2.days.from_now, timezone: "UTC")
    expect(post.reload.schedule_token).not_to eq(old)
    expect(Facebook::Posts::Publish.call(post: post, schedule_token: old, client: Facebook::GraphApi::MockClient.new).outcome).to eq(:stale_token)
  end

  it "sửa nội dung bài đã duyệt/lên lịch → về draft, mất phê duyệt" do
    described_class.submit(post, user: author)
    described_class.approve(post, user: approver)
    described_class.schedule(post, user: author, at: 1.day.from_now, timezone: "UTC")
    described_class.update_content(post, user: author, attrs: { message: "Nội dung mới hoàn toàn" })
    expect(post.reload.status).to eq("draft")
    expect(post.approved_by).to be_nil
  end

  it "auto-publish chỉ khi Page VÀ campaign bật; mặc định tắt" do
    campaign = create(:campaign, organization: org)
    p = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: author, campaign: campaign)
    described_class.submit(p, user: author)
    expect(p.reload.status).to eq("pending_approval")

    conn.update!(auto_publish_enabled: true)
    p2 = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: author, campaign: campaign)
    described_class.submit(p2, user: author)
    expect(p2.reload.status).to eq("pending_approval") # campaign chưa bật

    campaign.update!(facebook_auto_publish: true)
    p3 = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: author, campaign: campaign)
    expect { described_class.submit(p3, user: author) }.to have_enqueued_job(FacebookPublishJob)
    expect(p3.reload.status).to eq("scheduled")
    expect(p3.approval_source).to eq("auto_publish")
  end

  it "huỷ và thử lại" do
    described_class.submit(post, user: author)
    described_class.approve(post, user: approver)
    described_class.cancel(post, user: author)
    expect(post.reload.status).to eq("cancelled")
    described_class.reopen(post, user: author)
    expect(post.reload.status).to eq("draft")

    post.update_columns(status: "failed", last_error_code: "max_attempts_exhausted", attempts: 5)
    expect { described_class.retry(post, user: author) }.to have_enqueued_job(FacebookPublishJob)
    expect(post.reload.status).to eq("scheduled")
    expect(post.attempts).to eq(0)
  end

  it "retry bài không rõ kết quả cần xác nhận; retry khi Page chưa sẵn sàng bị chặn" do
    post.update_columns(status: "failed", last_error_code: "publish_state_unknown")
    expect { described_class.retry(post, user: author) }.to raise_error(Facebook::StateError)
    conn.update!(publishing_paused: true)
    expect { described_class.retry(post, user: author, confirm_unknown: true) }.to raise_error(Facebook::StateError, /Page chưa sẵn sàng/)
  end

  it "ngắt kết nối Page xoá token và đánh dấu bài đang chờ là failed" do
    described_class.submit(post, user: author)
    conn.disconnect!(user: author)
    expect(conn.reload.status).to eq("disconnected")
    expect(conn.access_token_ciphertext).to be_nil
    expect(post.reload.status).to eq("failed")
    expect(post.last_error_code).to eq("page_disconnected")
  end
end
