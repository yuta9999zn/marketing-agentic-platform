require "rails_helper"

# Request spec: dùng ĐÚNG tên trường đọc từ form đã render (như trình duyệt),
# kiểm tra quyền và cách ly workspace.
RSpec.describe "Facebook groups + group shares", type: :request do
  include ActiveJob::TestHelper

  let(:org) { create(:organization) }
  let(:owner) { create(:user, name: "Chủ") }
  let(:copywriter) { create(:user, name: "Biên tập") }
  let(:client_user) { create(:user) }
  let!(:m1) { create(:membership, organization: org, user: owner, role: "owner") }
  let!(:m2) { create(:membership, organization: org, user: copywriter, role: "copywriter") }
  let!(:m3) { create(:membership, organization: org, user: client_user, role: "client") }
  let!(:conn) { create(:facebook_page_connection, organization: org) }
  let(:fb_post) { create(:facebook_post, :published, organization: org, facebook_page_connection: conn, title: "Căn hộ Cầu Giấy") }

  def form_names(html, action)
    form = Nokogiri::HTML(html).css("form[action='#{action}']").first
    raise "không thấy form #{action}" if form.nil?

    form.css("[name]").map { |n| n["name"] }
  end

  it "thêm nhóm qua form thật (tên trường group[...]), danh sách hiển thị, sửa được" do
    login_as(copywriter)
    get new_facebook_group_path
    expect(response).to have_http_status(:ok)
    expect(form_names(response.body, facebook_groups_path)).to include("group[name]", "group[url]", "group[tags]",
                                                                       "group[rules_note]", "group[allows_links]",
                                                                       "group[default_assignee_id]")
    post facebook_groups_path, params: { group: { name: "Mua bán căn hộ Cầu Giấy", url: "https://www.facebook.com/groups/cangiay?ref=share",
                                                  tags: "Cầu Giấy, căn hộ", rules_note: "Cấm link", allows_links: "0" } }
    group = org.facebook_groups.last
    expect(response).to redirect_to(facebook_groups_path)
    expect(group.url).to eq("https://www.facebook.com/groups/cangiay")
    expect(group.allows_links).to be false

    get facebook_groups_path
    expect(response.body).to include("Mua bán căn hộ Cầu Giấy", "Cấm link")
    get facebook_groups_path(tag: "Cầu Giấy")
    expect(response.body).to include("Mua bán căn hộ Cầu Giấy")

    patch facebook_group_path(group), params: { group: { name: "Đổi tên" } }
    expect(group.reload.name).to eq("Đổi tên")
  end

  it "link sai hiện lỗi tiếng Việt trên form" do
    login_as(owner)
    post facebook_groups_path, params: { group: { name: "X", url: "https://www.facebook.com/KaoriRealEstate" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("phải là link nhóm dạng")
    expect(response.body).not_to include("Translation missing")
  end

  it "copywriter không xoá được nhóm; owner xoá nhóm chưa dùng, nhóm đã dùng thì chỉ ẩn" do
    unused = create(:facebook_group, organization: org)
    used = create(:facebook_group, organization: org)
    FacebookGroupShare.create!(organization: org, facebook_post: fb_post, facebook_group: used, assignee: owner, scheduled_at: 1.hour.from_now)

    login_as(copywriter)
    delete facebook_group_path(unused)
    expect(FacebookGroup.exists?(unused.id)).to be true

    login_as(owner)
    delete facebook_group_path(unused)
    expect(FacebookGroup.exists?(unused.id)).to be false
    delete facebook_group_path(used)
    expect(used.reload.active).to be false
  end

  it "trang bài đã đăng có form lên kế hoạch; gửi đúng tên trường tạo lượt chia sẻ + lời nhắc" do
    g1 = create(:facebook_group, organization: org, name: "Nhóm A")
    g2 = create(:facebook_group, organization: org, name: "Nhóm B", default_assignee: copywriter)
    login_as(owner)
    get facebook_post_path(fb_post)
    names = form_names(response.body, facebook_post_group_shares_path(fb_post))
    expect(names).to include("group_ids[]", "start_at", "spacing_minutes", "assignee_id", "ai_variants")

    start = 2.hours.from_now.in_time_zone(fb_post.timezone).strftime("%Y-%m-%dT%H:%M")
    expect do
      post facebook_post_group_shares_path(fb_post), params: { group_ids: [ g1.id, g2.id ], start_at: start,
                                                              spacing_minutes: "45", assignee_id: "", ai_variants: "1" }
    end.to change(FacebookGroupShare, :count).by(2).and have_enqueued_job(ReminderDispatchJob).exactly(2).times
    expect(response).to redirect_to(facebook_post_path(fb_post, anchor: "group-shares"))
    shares = fb_post.facebook_group_shares.chronological
    expect(shares.map(&:assignee)).to eq([ owner, copywriter ])
    expect((shares.last.scheduled_at - shares.first.scheduled_at).to_i).to eq(45 * 60)
    expect(shares.map(&:ai_variant)).to all(be true) # AI_PROVIDER=fake chạy ngay

    follow_redirect!
    expect(response.body).to include("Nhóm A", "Nhóm B", "Sao chép nội dung", "Mở nhóm")
  end

  it "bài chưa đăng không có form lên kế hoạch và không tạo được lượt chia sẻ" do
    draft = create(:facebook_post, organization: org, facebook_page_connection: conn)
    g1 = create(:facebook_group, organization: org)
    login_as(owner)
    get facebook_post_path(draft)
    expect(response.body).not_to include(facebook_post_group_shares_path(draft))
    post facebook_post_group_shares_path(draft), params: { group_ids: [ g1.id ] }
    expect(FacebookGroupShare.count).to eq(0)
  end

  it "hàng đợi: thẻ có nội dung + nút sao chép; đánh dấu đã đăng bằng form của thẻ" do
    g1 = create(:facebook_group, organization: org, name: "Nhóm Đến Giờ")
    share = FacebookGroupShare.create!(organization: org, facebook_post: fb_post, facebook_group: g1, assignee: copywriter,
                                       scheduled_at: 5.minutes.ago)
    login_as(copywriter)
    get facebook_group_shares_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nhóm Đến Giờ", fb_post.message.split.first, 'data-action="clipboard#copy"')
    expect(response.body).to include(fb_post.permalink_url) # nút sao chép link (nhóm cho link)

    names = form_names(response.body, complete_facebook_group_share_path(share))
    expect(names).to include("group_post_url", "note", "status")
    post complete_facebook_group_share_path(share), params: { status: "posted", group_post_url: "https://www.facebook.com/groups/x/posts/1" },
                                                    headers: { "HTTP_REFERER" => facebook_group_shares_url }
    expect(response).to redirect_to(facebook_group_shares_url)
    expect(share.reload).to be_posted

    get facebook_group_shares_path(filter: "done")
    expect(response.body).to include("Xem bài trong nhóm")
    get facebook_group_shares_path(filter: "today")
    expect(response.body).not_to include("Nhóm Đến Giờ")
  end

  it "đổi giờ và người phụ trách qua form của thẻ" do
    g1 = create(:facebook_group, organization: org)
    share = FacebookGroupShare.create!(organization: org, facebook_post: fb_post, facebook_group: g1, assignee: owner,
                                       scheduled_at: 1.hour.from_now)
    login_as(owner)
    get facebook_group_shares_path(filter: "all", mine: "0")
    names = Nokogiri::HTML(response.body).css("form[action='#{facebook_group_share_path(share)}']").flat_map { |f| f.css("[name]").map { |n| n["name"] } }
    expect(names).to include("scheduled_at", "assignee_id", "message")
    new_time = 4.hours.from_now.in_time_zone(share.timezone).change(sec: 0)
    patch facebook_group_share_path(share), params: { scheduled_at: new_time.strftime("%Y-%m-%dT%H:%M"), assignee_id: copywriter.id }
    share.reload
    expect(share.scheduled_at).to eq(new_time)
    expect(share.assignee).to eq(copywriter)
  end

  it "client bị chặn; không thao tác được nhóm/lượt chia sẻ của workspace khác" do
    other_org = create(:organization)
    other_conn = create(:facebook_page_connection, organization: other_org)
    other_post = create(:facebook_post, :published, organization: other_org, facebook_page_connection: other_conn)
    other_group = create(:facebook_group, organization: other_org)
    other_owner = create(:user)
    create(:membership, organization: other_org, user: other_owner, role: "owner")
    foreign_share = FacebookGroupShare.create!(organization: other_org, facebook_post: other_post, facebook_group: other_group,
                                               assignee: other_owner, scheduled_at: 1.hour.from_now)

    login_as(client_user)
    get facebook_group_shares_path
    expect(response).to redirect_to(root_path)
    get facebook_groups_path
    expect(response).to redirect_to(root_path)

    login_as(owner)
    get edit_facebook_group_path(other_group)
    expect(response).to redirect_to(root_path)
    post complete_facebook_group_share_path(foreign_share), params: { status: "posted" }
    expect(foreign_share.reload).to be_pending
    post facebook_post_group_shares_path(fb_post), params: { group_ids: [ other_group.id ] }
    expect(FacebookGroupShare.where(facebook_post: fb_post)).to be_empty
  end

  it "sidebar hiện số việc chia sẻ đến hạn của tôi" do
    g1 = create(:facebook_group, organization: org)
    FacebookGroupShare.create!(organization: org, facebook_post: fb_post, facebook_group: g1, assignee: owner, scheduled_at: 1.minute.ago)
    login_as(owner)
    get root_path
    link = Nokogiri::HTML(response.body).css("a.nav-item[href='#{facebook_group_shares_path}']").first
    expect(link).to be_present
    expect(link.at_css(".count")&.text).to eq("1")
  end
end
