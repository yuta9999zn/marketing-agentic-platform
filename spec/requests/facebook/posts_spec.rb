require "rails_helper"

RSpec.describe "Facebook posts", type: :request do
  include ActiveJob::TestHelper

  let(:org) { create(:organization) }
  let(:owner) { create(:user) }
  let(:copywriter) { create(:user) }
  let(:client_user) { create(:user) }
  let!(:m1) { create(:membership, organization: org, user: owner, role: "owner") }
  let!(:m2) { create(:membership, organization: org, user: copywriter, role: "copywriter") }
  let!(:m3) { create(:membership, organization: org, user: client_user, role: "client") }
  let!(:conn) { create(:facebook_page_connection, organization: org) }
  let(:other_org) { create(:organization) }
  let!(:other_conn) { create(:facebook_page_connection, organization: other_org) }

  it "AI generate tạo draft; copywriter gửi duyệt nhưng KHÔNG duyệt được; owner duyệt; lên lịch đúng múi giờ" do
    login_as(copywriter)
    post generate_facebook_posts_path, params: { brief: "Ra mắt sản phẩm mới" }
    fb_post = FacebookPost.last
    expect(response).to redirect_to(facebook_post_path(fb_post))
    expect(fb_post.status).to eq("draft")
    expect(fb_post.ai_generated).to be true

    post submit_facebook_post_path(fb_post)
    expect(fb_post.reload.status).to eq("pending_approval")

    post approve_facebook_post_path(fb_post)
    expect(response).to redirect_to(root_path) # không có quyền approve
    expect(fb_post.reload.status).to eq("pending_approval")

    login_as(owner)
    post approve_facebook_post_path(fb_post)
    expect(fb_post.reload.status).to eq("approved")
    expect(fb_post.approved_by).to eq(owner)

    expect {
      post schedule_facebook_post_path(fb_post), params: { scheduled_at: "2026-12-24T20:30", timezone: "Asia/Ho_Chi_Minh" }
    }.to have_enqueued_job(FacebookPublishJob)
    expect(fb_post.reload.status).to eq("scheduled")
    expect(fb_post.scheduled_at.utc).to eq(Time.utc(2026, 12, 24, 13, 30))

    get facebook_post_path(fb_post)
    expect(response.body).to include("20:30")
    get facebook_posts_path(filter: "scheduled")
    expect(response.body).to include(fb_post.title)
  end

  it "publish_now cần bài đã approved; draft bị từ chối" do
    login_as(owner)
    fb_post = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: owner)
    post publish_now_facebook_post_path(fb_post)
    expect(flash[:alert]).to be_present
    expect(fb_post.reload.status).to eq("draft")
  end

  it "sửa bài đã duyệt → về draft; reject ghi lý do" do
    login_as(owner)
    fb_post = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: owner)
    post submit_facebook_post_path(fb_post)
    post reject_facebook_post_path(fb_post), params: { note: "Thiếu hashtag" }
    expect(fb_post.reload.status).to eq("draft")
    expect(fb_post.rejection_note).to eq("Thiếu hashtag")
    post submit_facebook_post_path(fb_post)
    post approve_facebook_post_path(fb_post)
    patch facebook_post_path(fb_post), params: { post: { message: "Đã sửa nội dung khác" } }
    expect(fb_post.reload.status).to eq("draft")
  end

  it "tạo bài thủ công kèm ảnh → post_type photo, ảnh lưu Active Storage" do
    login_as(owner)
    file = Rack::Test::UploadedFile.new(StringIO.new("\x89PNGfake"), "image/png", original_filename: "a.png")
    post facebook_posts_path, params: { post: { title: "Ảnh", message: "Caption", image: file, timezone: "UTC" } }
    fb_post = FacebookPost.last
    expect(fb_post.post_type).to eq("photo")
    expect(fb_post.image).to be_attached
    get facebook_post_path(fb_post)
    expect(response).to have_http_status(:ok)
  end

  # Hồi quy: form phải gửi đúng scope mà controller đọc (params[:post]).
  # Trước đây form_with model sinh "facebook_post[...]" → mọi trường bị bỏ qua.
  it "form tạo/sửa bài gửi tên trường khớp controller (tạo thật qua tên trường của form)" do
    login_as(owner)
    get new_facebook_post_path
    form = Nokogiri::HTML(response.body).css("form[action='#{facebook_posts_path}']").last
    names = form.css("[name]").map { |n| n["name"] }
    expect(names).to include("post[message]", "post[title]", "post[scheduled_at]", "post[timezone]", "post[image]")
    expect(names.grep(/\Afacebook_post\[/)).to be_empty

    fields = { "post[title]" => "Thủ công", "post[message]" => "Nội dung từ form",
               "post[post_type]" => "text", "post[timezone]" => "Asia/Ho_Chi_Minh" }
    expect(names).to include(*fields.keys)
    post facebook_posts_path, params: Rack::Utils.parse_nested_query(Rack::Utils.build_query(fields))
    fb_post = FacebookPost.last
    expect(response).to redirect_to(facebook_post_path(fb_post))
    expect(fb_post.message).to eq("Nội dung từ form")
    expect(fb_post.title).to eq("Thủ công")

    get edit_facebook_post_path(fb_post)
    edit_form = Nokogiri::HTML(response.body).css("form[action='#{facebook_post_path(fb_post)}']").first
    expect(edit_form.css("[name]").map { |n| n["name"] }).to include("post[message]")
  end

  it "lỗi validation hiển thị tiếng Việt, không lộ 'Translation missing'" do
    login_as(owner)
    post facebook_posts_path, params: { post: { message: "", timezone: "UTC" } }
    follow_redirect!
    expect(response.body).not_to include("Translation missing")
    expect(response.body).to include("Nội dung bài đăng không được để trống")
  end

  it "multi-tenant: không xem/duyệt được bài của org khác" do
    foreign = create(:facebook_post, organization: other_org, facebook_page_connection: other_conn)
    login_as(owner)
    get facebook_post_path(foreign)
    expect(response).to redirect_to(root_path)
    post approve_facebook_post_path(foreign)
    expect(foreign.reload.status).to eq("draft")
  end

  it "client không vào được khu vực bài đăng" do
    login_as(client_user)
    get facebook_posts_path
    expect(response).to redirect_to(root_path)
    get new_facebook_post_path
    expect(response).to redirect_to(root_path)
  end

  it "retry bài thất bại và index các bộ lọc render được" do
    login_as(owner)
    fb_post = create(:facebook_post, organization: org, facebook_page_connection: conn, created_by: owner)
    fb_post.update_columns(status: "failed", last_error_code: "transient", error_kind: "transient")
    fb_post.facebook_publish_attempts.create!(attempt_number: 1, outcome: "transient_failure", error_code: "4", error_message: "rate")
    %w[all pending scheduled published failed drafts].each do |f|
      get facebook_posts_path(filter: f)
      expect(response).to have_http_status(:ok)
    end
    expect { post retry_facebook_post_path(fb_post) }.to have_enqueued_job(FacebookPublishJob)
    expect(fb_post.reload.status).to eq("scheduled")
  end
end
