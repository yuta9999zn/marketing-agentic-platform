require "rails_helper"

RSpec.describe "Facebook dispatch & reconcile" do
  include ActiveJob::TestHelper

  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let!(:m) { create(:membership, organization: org, user: user, role: "owner") }
  let(:conn) { create(:facebook_page_connection, organization: org) }

  it "FacebookDispatchDueJob enqueue bài tới giờ, bỏ qua bài chưa tới" do
    due = create(:facebook_post, organization: org, facebook_page_connection: conn, status: "draft")
    due.update_columns(status: "scheduled", scheduled_at: 1.minute.ago, schedule_token: "t1")
    future = create(:facebook_post, organization: org, facebook_page_connection: conn)
    future.update_columns(status: "scheduled", scheduled_at: 1.hour.from_now, schedule_token: "t2")
    expect { FacebookDispatchDueJob.perform_now }.to have_enqueued_job(FacebookPublishJob).with(due.id, "t1").exactly(:once)
  end

  it "FacebookPublishJob đăng bài tới giờ qua mock client (ENV FACEBOOK_MOCK_MODE)" do
    post = create(:facebook_post, organization: org, facebook_page_connection: conn)
    post.update_columns(status: "scheduled", scheduled_at: 1.minute.ago, schedule_token: "tok")
    with_env("FACEBOOK_MOCK_MODE" => "true") do
      Facebook::GraphApi::MockClient.reset!
      FacebookPublishJob.perform_now(post.id, "tok")
    end
    expect(post.reload.status).to eq("published")
    expect(post.published_via).to eq("mock")
  end

  it "Reconcile: bài kẹt ở publishing có trên feed → published; không có → failed publish_state_unknown" do
    stuck = create(:facebook_post, organization: org, facebook_page_connection: conn, message: "Bài đã lên")
    stuck.update_columns(status: "publishing", publish_started_at: 20.minutes.ago)
    client = Facebook::GraphApi::MockClient.new
    client.post("/#{conn.page_id}/feed", message: "Bài đã lên", access_token: "x")
    expect(Facebook::Posts::Reconcile.call(post: stuck, client: client)).to eq(:published)
    expect(stuck.reload.status).to eq("published")
    expect(stuck.facebook_post_id).to be_present

    stuck2 = create(:facebook_post, organization: org, facebook_page_connection: conn, message: "Chưa lên")
    stuck2.update_columns(status: "publishing", publish_started_at: 20.minutes.ago)
    expect(Facebook::Posts::Reconcile.call(post: stuck2, client: client)).to eq(:unknown)
    expect(stuck2.reload.status).to eq("failed")
    expect(stuck2.last_error_code).to eq("publish_state_unknown")
  end

  it "Mock mode bị tắt trên production" do
    allow(Rails.env).to receive(:production?).and_return(true)
    with_env("FACEBOOK_MOCK_MODE" => "true") do
      expect(Facebook::Config.mock_mode?).to be false
      expect(Facebook::Config.mode).to eq(:unconfigured)
    end
  end
end
