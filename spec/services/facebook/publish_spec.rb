require "rails_helper"

# Toàn bộ test này dùng MockClient / client giả — KHÔNG gọi Meta thật.
RSpec.describe Facebook::Posts::Publish do
  include ActiveJob::TestHelper

  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let!(:membership) { create(:membership, organization: org, user: user, role: "owner") }
  let(:conn) { create(:facebook_page_connection, organization: org) }
  let(:client) { Facebook::GraphApi::MockClient.new }

  def scheduled_post(**attrs)
    post = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: user, **attrs)
    Facebook::Posts::Transitions.submit(post, user: user)
    Facebook::Posts::Transitions.approve(post, user: user)
    Facebook::Posts::Transitions.schedule(post, user: user, at: Time.current, timezone: "UTC", publish_now: true)
    post.reload
  end

  it "đăng bài text qua /{page}/feed, lưu post id + permalink, đánh dấu mock" do
    post = scheduled_post
    result = described_class.call(post: post, schedule_token: post.schedule_token, client: client)
    expect(result.outcome).to eq(:published)
    post.reload
    expect(post.status).to eq("published")
    expect(post.facebook_post_id).to start_with("#{conn.page_id}_mock")
    expect(post.permalink_url).to include("facebook.com")
    expect(post.published_via).to eq("mock")
    expect(post.facebook_publish_attempts.last.outcome).to eq("success")
    expect(client.calls.map { |c| c[:path] }).to include("/#{conn.page_id}/feed")
    expect(AuditLog.where(action: "facebook.post.published").count).to eq(1)
  end

  it "KHÔNG đăng bài chưa qua approved (draft / pending_approval)" do
    draft = create(:facebook_post, organization: org, facebook_page_connection: conn, scheduled_at: 1.minute.ago)
    expect(described_class.call(post: draft, client: client).outcome).to eq(:not_scheduled)
    Facebook::Posts::Transitions.submit(draft, user: user)
    expect(described_class.call(post: draft.reload, client: client).outcome).to eq(:not_scheduled)
    expect(client.calls).to be_empty
    expect(draft.reload.status).to eq("pending_approval")
  end

  it "schedule_token lệch (đã đổi lịch/huỷ) → job cũ bỏ qua, không gọi API" do
    post = scheduled_post
    expect(described_class.call(post: post, schedule_token: "stale", client: client).outcome).to eq(:stale_token)
    expect(client.calls).to be_empty
  end

  it "idempotent: gọi lần hai sau khi đã published không đăng lại" do
    post = scheduled_post
    described_class.call(post: post, schedule_token: post.schedule_token, client: client)
    described_class.call(post: post, schedule_token: post.schedule_token, client: client)
    expect(client.calls.count { |c| c[:path].end_with?("/feed") }).to eq(1)
    expect(post.reload.facebook_publish_attempts.count).to eq(1)
  end

  it "lỗi rate limit (tạm thời) → scheduled lại với backoff, tăng attempts, enqueue job" do
    post = scheduled_post
    client.fail_next!(Facebook::ApiError.new("Rate limited", code: 4))
    result = nil
    expect { result = described_class.call(post: post, schedule_token: post.schedule_token, client: client) }
      .to have_enqueued_job(FacebookPublishJob)
    expect(result.outcome).to eq(:retry_scheduled)
    post.reload
    expect(post.status).to eq("scheduled")
    expect(post.attempts).to eq(1)
    expect(post.next_attempt_at).to be > Time.current + 50.seconds
    expect(post.facebook_publish_attempts.last.outcome).to eq("transient_failure")
  end

  it "hết max_attempts → failed, không retry vô hạn" do
    post = scheduled_post
    post.update_columns(max_attempts: 2)
    2.times do
      client.fail_next!(Facebook::ApiError.new("boom", code: 2))
      post.update_columns(next_attempt_at: 1.second.ago)
      described_class.call(post: post, schedule_token: post.reload.schedule_token, client: client)
    end
    post.reload
    expect(post.status).to eq("failed")
    expect(post.last_error_code).to eq("max_attempts_exhausted")
    expect(post.attempts).to eq(2)
  end

  it "token hết hạn (190) → failed ngay, kết nối chuyển token_expired, không retry" do
    post = scheduled_post
    client.fail_next!(Facebook::ApiError.new("Error validating access token", code: 190, subcode: 463))
    expect { described_class.call(post: post, schedule_token: post.schedule_token, client: client) }
      .not_to have_enqueued_job(FacebookPublishJob)
    expect(post.reload.status).to eq("failed")
    expect(post.error_kind).to eq("permanent")
    expect(post.last_error_code).to eq("token_expired")
    expect(conn.reload.status).to eq("token_expired")
  end

  it "thiếu quyền (code 200) → failed vĩnh viễn, kết nối permission_missing" do
    post = scheduled_post
    client.fail_next!(Facebook::ApiError.new("Requires pages_manage_posts", code: 200))
    described_class.call(post: post, schedule_token: post.schedule_token, client: client)
    expect(post.reload.last_error_code).to eq("permission")
    expect(conn.reload.status).to eq("permission_missing")
  end

  it "lỗi mạng → tạm thời, retry" do
    post = scheduled_post
    client.fail_next!(Facebook::NetworkError.new("timeout"))
    result = described_class.call(post: post, schedule_token: post.schedule_token, client: client)
    expect(result.outcome).to eq(:retry_scheduled)
  end

  it "kill switch workspace → bài giữ nguyên scheduled, không gọi API, ghi attempt skipped" do
    post = scheduled_post
    org.update!(facebook_publishing_paused: true)
    expect(described_class.call(post: post, schedule_token: post.schedule_token, client: client).outcome).to eq(:paused)
    expect(post.reload.status).to eq("scheduled")
    expect(client.calls).to be_empty
    expect(post.facebook_publish_attempts.last.outcome).to eq("skipped")
  end

  it "ENV FACEBOOK_PUBLISHING_ENABLED=false → paused" do
    post = scheduled_post
    with_env("FACEBOOK_PUBLISHING_ENABLED" => "false") do
      expect(described_class.call(post: post, schedule_token: post.schedule_token, client: client).outcome).to eq(:paused)
    end
  end

  it "từ khoá chặn → failed permanent trước khi gọi API" do
    post = scheduled_post(message: "Cam kết chữa khỏi 100%")
    conn.update!(blocked_terms: "chữa khỏi\nlừa đảo")
    expect(described_class.call(post: post, schedule_token: post.schedule_token, client: client).outcome).to eq(:invalid)
    expect(post.reload.status).to eq("failed")
    expect(post.last_error_code).to eq("blocked_term")
    expect(client.calls).to be_empty
  end

  it "Meta không trả id → không đánh dấu published" do
    fake = Class.new do
      def mock? = true
      def post(*) = {}
      def get(*) = {}
    end.new
    post = scheduled_post
    described_class.call(post: post, schedule_token: post.schedule_token, client: fake)
    expect(post.reload.status).to eq("failed")
    expect(post.facebook_post_id).to be_nil
  end

  it "bài ảnh đi qua /{page}/photos multipart và lấy post_id" do
    post = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: user, post_type: "photo")
    post.image.attach(io: StringIO.new("\x89PNG\r\n\x1a\nfakepng"), filename: "a.png", content_type: "image/png")
    Facebook::Posts::Transitions.submit(post, user: user)
    Facebook::Posts::Transitions.approve(post, user: user)
    Facebook::Posts::Transitions.schedule(post, user: user, at: Time.current, timezone: "UTC", publish_now: true)
    described_class.call(post: post.reload, schedule_token: post.schedule_token, client: client)
    expect(post.reload.status).to eq("published")
    expect(client.calls.map { |c| c[:path] }).to include("/#{conn.page_id}/photos")
    expect(post.facebook_post_id).to start_with("#{conn.page_id}_")
  end

  it "bài ảnh không có ảnh → failed image_missing" do
    post = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: user, post_type: "photo")
    expect { Facebook::Posts::Transitions.submit(post, user: user) }.to raise_error(Facebook::ValidationError, /image_missing/)
  end
end
