# Dữ liệu demo — email/mật khẩu là dữ liệu giả, không phải người thật.
# Idempotent: chạy lại không nhân bản dữ liệu.
puts "Seeding MarketingOS demo data..."

org = Organization.find_or_create_by!(slug: "nova-agency") do |o|
  o.name = "Nova Agency (demo)"
end

users = {
  owner: User.find_or_create_by!(email: "owner@demo.vn") do |u|
    u.name = "Lan Chủ tịch"; u.password = "password123"
  end,
  manager: User.find_or_create_by!(email: "manager@demo.vn") do |u|
    u.name = "Minh Quản lý"; u.password = "password123"
  end,
  strategist: User.find_or_create_by!(email: "strategist@demo.vn") do |u|
    u.name = "Hoa Chiến lược"; u.password = "password123"
  end,
  copywriter: User.find_or_create_by!(email: "copy@demo.vn") do |u|
    u.name = "Tuấn Content"; u.password = "password123"
  end,
  designer: User.find_or_create_by!(email: "design@demo.vn") do |u|
    u.name = "Ngọc Design"; u.password = "password123"
  end,
  approver: User.find_or_create_by!(email: "approver@demo.vn") do |u|
    u.name = "Bà Duyệt"; u.password = "password123"
  end,
  client: User.find_or_create_by!(email: "client@demo.vn") do |u|
    u.name = "Anh Khách"; u.password = "password123"
  end
}

{ owner: "owner", manager: "manager", strategist: "strategist",
  copywriter: "copywriter", designer: "designer",
  approver: "approver", client: "client" }.each do |key, role|
  Membership.find_or_create_by!(organization: org, user: users[key]) { |m| m.role = role }
end

# ── Project templates (Phase 2) ──────────────────────────────
template_specs = [
  ["Social Campaign", "Chiến dịch social đa kênh: brief → persona → content plan → bài đăng.", {
    "milestones" => [{ "title" => "Brief & Strategy", "offset_days" => 5 },
                     { "title" => "Content Production", "offset_days" => 20 },
                     { "title" => "Launch", "offset_days" => 30 }],
    "tasks" => [{ "title" => "Chốt brief với client", "milestone" => "Brief & Strategy", "priority" => "high", "offset_days" => 3 },
                { "title" => "Bộ bài đăng tuần 1", "milestone" => "Content Production", "priority" => "medium", "offset_days" => 15 }]
  }],
  ["Video Launch", "Ra mắt sản phẩm bằng video ngắn + teaser.", {
    "milestones" => [{ "title" => "Kịch bản", "offset_days" => 7 }, { "title" => "Sản xuất", "offset_days" => 21 }],
    "tasks" => [{ "title" => "Viết kịch bản video", "milestone" => "Kịch bản", "priority" => "high", "offset_days" => 6 },
                { "title" => "Quay dựng teaser", "milestone" => "Sản xuất", "priority" => "urgent", "offset_days" => 18 }]
  }],
  ["Event", "Sự kiện/khách hàng offline: run-of-show + truyền thông.", {
    "milestones" => [{ "title" => "Kế hoạch sự kiện", "offset_days" => 10 }, { "title" => "Ngày sự kiện", "offset_days" => 30 }],
    "tasks" => [{ "title" => "Run-of-show", "milestone" => "Kế hoạch sự kiện", "priority" => "high", "offset_days" => 8 }]
  }],
  ["Email Launch", "Chuỗi email ra mắt sản phẩm.", {
    "milestones" => [{ "title" => "Email flow", "offset_days" => 7 }],
    "tasks" => [{ "title" => "Viết 3 email chuỗi", "milestone" => "Email flow", "priority" => "medium", "offset_days" => 5 }]
  }],
  ["Content Calendar", "Lịch nội dung 4 tuần theo kênh.", {
    "milestones" => [{ "title" => "Lịch nội dung", "offset_days" => 4 }],
    "tasks" => [{ "title" => "Lên content plan 4 tuần", "milestone" => "Lịch nội dung", "priority" => "high", "offset_days" => 3 }]
  }]
]
template_specs.each do |name, desc, config|
  ProjectTemplate.find_or_create_by!(organization: org, name: name) do |t|
    t.description = desc; t.config = config; t.owner = users[:owner]
  end
end

# ── Prompt templates: quy trình marketing chuẩn cho từng loại nội dung ──
prompt_specs = [
  ["Brief tiếp nhận yêu cầu", "brief", <<~I, "1. Bối cảnh & mục tiêu kinh doanh\n2. Đối tượng mục tiêu\n3. Thông điệp chính\n4. Kênh & định dạng\n5. KPI đo lường\n6. Ràng buộc (ngân sách, thời hạn, pháp lý)\n7. Câu hỏi còn thiếu"],
    Thu thập và hệ thống hóa yêu cầu theo quy trình tiếp nhận brief của agency:
    - Làm rõ mục tiêu KINH DOANH đứng sau yêu cầu marketing (doanh số, nhận biết, giữ chân).
    - Xác định đối tượng mục tiêu và bối cảnh cạnh tranh.
    - Chốt thông điệp cốt lõi, kênh triển khai, KPI đo lường.
    - Liệt kê ràng buộc: ngân sách, thời hạn, yêu cầu pháp lý/thương hiệu.
    - Mọi thông tin chưa có trong dữ liệu đầu vào phải đưa vào missing_data để hỏi lại client.
  I
  ["Chân dung khách hàng", "persona", <<~I, "Tên & mô tả 1 dòng · Nhân khẩu học · Một ngày điển hình · Nỗi đau · Động lực · Rào cản mua hàng · Kênh tiếp cận · Câu nói tiêu biểu"],
    Xây chân dung khách hàng dựa trên dữ liệu brief và khảo sát đã có:
    - Nhân khẩu học và bối cảnh sống/làm việc.
    - Nỗi đau cụ thể mà sản phẩm giải quyết, xếp theo mức độ cấp thiết.
    - Động lực mua và rào cản khiến họ chần chừ.
    - Kênh truyền thông họ thực sự dùng, thời điểm tiếp cận tốt nhất.
    Không suy diễn số liệu nhân khẩu học nếu brief chưa cung cấp — ghi vào missing_data.
  I
  ["Kịch bản video ngắn 30 giây", "video_script", <<~I, "Hook (0-3s) · Vấn đề (3-8s) · Giải pháp (8-20s) · Bằng chứng (20-25s) · CTA (25-30s) · Ghi chú sản xuất"],
    Viết kịch bản video dạng dọc 9:16 cho mạng xã hội:
    - Hook 3 giây đầu phải chạm đúng nỗi đau trong persona, không mở bài chung chung.
    - Mỗi cảnh ghi rõ: hình ảnh thấy gì, lời thoại/voice-over, chữ trên màn hình.
    - Bằng chứng phải lấy từ brief (số liệu, chứng nhận, review) — không có thì ghi missing_data.
    - Kết bằng một CTA duy nhất, rõ hành động.
  I
  ["Bài đăng mạng xã hội", "social_post", <<~I, "Hook · Thân bài (2-3 ý) · CTA · Hashtag · Gợi ý hình ảnh"],
    Viết bài đăng theo chuẩn nội dung mạng xã hội:
    - Câu đầu tiên là hook, đứng độc lập được khi bị cắt bởi nút "xem thêm".
    - Thân bài tối đa 3 ý, mỗi ý một dòng ngắn, bám thông điệp brief.
    - Một CTA duy nhất; hashtag đúng ngành, không nhồi.
    - Gợi ý hình ảnh/video đi kèm để designer thực hiện.
  I
  ["Email marketing", "email", <<~I, "Subject (≤50 ký tự) · Preview text · Mở bài · Giá trị chính · Bằng chứng · CTA · Footer"],
    Viết email theo quy trình: mục tiêu email → đối tượng nhận → hành động mong muốn.
    - Subject dưới 50 ký tự, nói lợi ích chứ không nói tính năng; kèm 2 phương án A/B.
    - Preview text bổ sung cho subject, không lặp lại.
    - Thân email: một thông điệp chính duy nhất, dẫn tới một CTA.
    - Luôn có footer hủy đăng ký. Không dùng ngôn ngữ gây hiểu nhầm là thư giao dịch.
  I
  ["Nội dung quảng cáo", "ad_copy", <<~I, "Headline (3 biến thể) · Primary text · Description · CTA button · Ghi chú nhắm mục tiêu"],
    Viết nội dung quảng cáo trả phí theo cấu trúc đau khổ → giải pháp → hành động:
    - 3 biến thể headline để chạy A/B, mỗi biến thể một góc tiếp cận khác nhau.
    - Primary text nêu nỗi đau trong 1 câu, giải pháp trong 1 câu, bằng chứng trong 1 câu.
    - Tuân thủ chính sách quảng cáo: không cam kết kết quả tuyệt đối, không so sánh trực tiếp đối thủ.
  I
  ["Kịch bản chạy sự kiện", "event_run_of_show", <<~I, "Bảng: Thời gian · Hạng mục · Người phụ trách · Ghi chú hậu cần · Phương án dự phòng"],
    Lập kịch bản chạy sự kiện (run of show) chi tiết theo mốc thời gian:
    - Chia theo block 5-15 phút từ lúc đón khách tới lúc kết thúc.
    - Mỗi block ghi rõ người phụ trách và hạng mục hậu cần (âm thanh, ánh sáng, tài liệu).
    - Có phương án dự phòng cho các rủi ro thường gặp: trễ giờ, sự cố kỹ thuật, khách VIP đến muộn.
  I
  ["Prompt tạo ảnh", "image_prompt", <<~I, "Chủ thể · Bối cảnh · Bố cục & góc máy · Ánh sáng · Bảng màu thương hiệu · Tỷ lệ khung · Loại trừ"],
    Xây prompt tạo ảnh có cấu trúc, bám nhận diện thương hiệu:
    - Mô tả chủ thể và bối cảnh cụ thể, tránh từ trừu tượng.
    - Nêu rõ bố cục, góc máy, ánh sáng, tâm trạng ảnh.
    - Bảng màu và yếu tố nhận diện lấy từ brand kit của khách hàng.
    - Danh sách loại trừ (không chữ, không logo giả, không watermark).
    - Ghi chú bản quyền: ảnh AI cần được duyệt trước khi dùng thương mại.
  I
]
prompt_specs.each do |name, category, instructions, output_format|
  PromptTemplate.find_or_create_by!(organization: org, name: name) do |t|
    t.category = category
    t.instructions = instructions
    t.output_format = output_format
    t.locale = "vi"
    t.owner = users[:strategist]
  end
end

acme = Client.find_or_create_by!(organization: org, name: "ACME Coffee") do |c|
  c.industry = "F&B"
  c.notes = "Chuỗi cà phê specialty 12 cửa hàng."
end
glow = Client.find_or_create_by!(organization: org, name: "Glow Cosmetics") do |c|
  c.industry = "Làm đẹp"
  c.notes = "Thương hiệu skincare thiên nhiên."
end

campaign = Campaign.find_or_create_by!(organization: org, client: acme, name: "ACME Summer Launch") do |c|
  c.status = "brief"
  c.objective = "Ra mắt dòng cold brew mùa hè, tăng 30% doanh số cửa hàng trong 2 tháng."
  c.audience = "Dân văn phòng 25–40 tuổi ở TP.HCM/HN, uống cà phê mỗi ngày."
  c.channels = "Facebook, TikTok, Email"
  c.owner = users[:manager]
  c.start_date = Date.current - 10
  c.end_date = Date.current + 50
  c.brief_data = {
    "business_goal" => "Tăng 30% doanh số cold brew trong 2 tháng hè.",
    "product_service" => "Dòng cold brew đóng chai, 3 vị.",
    "insight" => "Văn phòng bận rộn cần cà phê ngon nhanh, không xếp hàng.",
    "success_metrics" => "Doanh số cửa hàng, số đơn online, tỷ lệ mua lại.",
    "brand_voice" => "Gần gũi, trẻ, không sáo rỗng."
  }
end
Campaign.find_or_create_by!(organization: org, client: glow, name: "Glow Rebrand Teaser") do |c|
  c.status = "draft"
  c.objective = "Teaser nhận diện mới trước ra mắt Q4."
  c.owner = users[:manager]
end

CampaignCollaborator.find_or_create_by!(campaign: campaign, user: users[:client]) { |cc| cc.access = "comment" }

# ── Milestones thật cho ACME ─────────────────────────────────
ms_specs = [
  ["Brief & Strategy", 5, "completed"], ["Sản xuất nội dung", 25, "in_progress"], ["Launch", 45, "not_started"]
]
ms_specs.each_with_index do |(title, offset, state), i|
  campaign.milestones.find_or_create_by!(title: title) do |m|
    m.due_at = (campaign.start_date || Date.current) + offset.days
    m.state = state; m.owner = users[:manager]; m.position = i
  end
end

# ── Artifacts do AI tạo ──────────────────────────────────────
# Seeds chạy trong `db:prepare` khi container khởi động lần đầu. Nếu ở đây gọi
# model thật mà model chưa tải xong (hoặc dịch vụ AI chưa lên), seeds sẽ ném lỗi
# → db:prepare thất bại → container không khởi động được. Dữ liệu demo KHÔNG
# được phép chặn triển khai.
#
# Nên: provider fake thì tạo ngay (tức thì, offline); provider thật thì bỏ qua
# và hướng dẫn tạo sau từ giao diện. Lỗi bất ngờ cũng chỉ cảnh báo, không dừng.
def seed_ai_artifacts(campaign, users)
  unless Ai::Gateway.fake_provider?
    puts "  ↳ Bỏ qua nội dung mẫu do AI (đang dùng provider \"#{Ai::Gateway.provider_name}\"). " \
         "Tạo từ trang campaign khi model đã sẵn sàng."
    return
  end

  if campaign.artifacts.where(kind: "brief").none?
    Ai::Workflows::CampaignBrief.call(campaign: campaign, user: users[:strategist])
    Ai::Workflows::PersonaDraft.call(campaign: campaign, user: users[:strategist])
    Ai::Workflows::ContentPlan.call(campaign: campaign, user: users[:copywriter])
  end
  if campaign.artifacts.where(kind: "social_post").none?
    Ai::Workflows::ScriptDraft.call(campaign: campaign, user: users[:copywriter], kind: "social_post", channel: "Facebook")
    Ai::Workflows::ScriptDraft.call(campaign: campaign, user: users[:copywriter], kind: "video_script", channel: "TikTok")
  end
rescue StandardError => e
  puts "  ↳ Không tạo được nội dung mẫu bằng AI (#{e.class}). Bỏ qua — seeds vẫn hoàn tất."
end

seed_ai_artifacts(campaign, users)

brief = campaign.artifact_of_kind("brief").last
persona = campaign.artifact_of_kind("persona").last
plan = campaign.artifact_of_kind("content_plan").last
social = campaign.artifacts.where(kind: "social_post").last

# ── Vòng duyệt THẬT qua ApprovalRound (Phase 3) ──────────────
if brief && brief.approval_rounds.none? && brief.approval_status == "draft"
  round = Approvals::Submit.call(artifact: brief, user: users[:strategist],
                                 reviewers: [users[:approver]], quorum: 1)
  Approvals::Decide.call(round: round, user: users[:approver], decision: "approved",
                         note: "OK, chốt hướng cold brew.")
end
if social && social.approval_rounds.none? && social.approval_status == "draft"
  Approvals::Submit.call(artifact: social, user: users[:copywriter],
                         reviewers: [users[:approver], users[:manager]], due_date: 3.days.from_now.to_date)
end
persona&.update!(approval_status: "in_review")
plan&.update!(approval_status: "in_review")

# Góp ý theo artifact
if plan && !Comment.exists?(artifact: plan)
  campaign.comments.create!(artifact: plan, user: users[:manager],
    body: "Tuần 2 nên thêm video TikTok — client muốn nhấn kênh này.")
  campaign.comments.create!(artifact: plan, user: users[:approver],
    body: "Đồng ý cấu trúc, nhưng cần thêm CTA rõ cho email tuần 4.")
end
if persona && !Comment.exists?(artifact: persona)
  campaign.comments.create!(artifact: persona, user: users[:copywriter],
    body: "Persona khá ổn, bổ sung thói quen mua hàng online nữa nhé.")
end

# ── Tasks gắn milestone ──────────────────────────────────────
m_brief = campaign.milestones.find_by(title: "Brief & Strategy")
m_content = campaign.milestones.find_by(title: "Sản xuất nội dung")
task_specs = [
  ["Chốt brief với client", users[:manager], Date.current - 2, "done", "high", nil, m_brief],
  ["Chuyển brief sang bản tiếng Anh cho client review", users[:copywriter], Date.current - 1, "in_progress", "medium", nil, m_brief],
  ["Bộ ảnh sản phẩm cold brew", users[:designer], Date.current + 4, "open", "urgent", nil, m_content],
  ["Thu thập tài liệu thương hiệu (brand guideline)", users[:designer], Date.current + 1, "open", "high", nil, m_content],
  ["Góp ý kịch bản video TikTok", users[:manager], Date.current + 2, "open", "medium", nil, m_content],
  ["Chốt ưu đãi khai trương với client", users[:manager], Date.current + 3, "open", "high", "Chờ client phản hồi bảng giá linh kiện ly", m_content],
  ["Setup tracking UTM cho landing page", users[:strategist], Date.current - 4, "in_progress", "medium", nil, m_content]
]
task_specs.each do |title, assignee, due, status, priority, blocked, milestone|
  campaign.tasks.find_or_create_by!(title: title) do |t|
    t.assignee = assignee; t.due_date = due; t.status = status
    t.priority = priority; t.blocked_reason = blocked; t.milestone = milestone
  end
end

# ── Events + attendees + RSVP ────────────────────────────────
kickoff = campaign.events.find_or_create_by!(title: "Kickoff ACME Summer") do |e|
  e.starts_at = 7.days.from_now.change(hour: 9, min: 0)
  e.ends_at = 7.days.from_now.change(hour: 10, min: 0)
  e.location = "Google Meet"
  e.agenda = "Duyệt content plan + phân công sản xuất nội dung tuần 1–2"
end
weekly = campaign.events.find_or_create_by!(title: "Weekly update với client") do |e|
  e.starts_at = 2.days.from_now.change(hour: 15, min: 30)
  e.ends_at = 2.days.from_now.change(hour: 16, min: 0)
  e.location = "Zalo Meet"
  e.agenda = "Báo cáo tiến độ, chốt ưu đãi khai trương"
end
[kickoff, weekly].each do |ev|
  [users[:manager], users[:strategist], users[:copywriter], users[:client]].each do |u|
    EventAttendee.find_or_create_by!(event: ev, user: u) { |a| a.rsvp = "invited" }
  end
end
weekly.event_attendees.find_by(user: users[:manager])&.update!(rsvp: "yes")

# ── Reminder thật (in-app) ────────────────────────────────────
Reminder.schedule!(org: org, user: users[:manager], kind: "task_due_soon",
                   run_at: 1.day.from_now,
                   payload: { "task" => "Chốt ưu đãi khai trương với client" },
                   idempotency_key: "seed:task_due_soon:manager")
Reminder.schedule!(org: org, user: users[:approver], kind: "review_requested",
                   run_at: 4.hours.from_now,
                   payload: { "artifact" => social&.title.to_s },
                   idempotency_key: "seed:review:approver")

campaign.comments.find_or_create_by!(user: users[:manager], body: "Client muốn nhấn mạnh nguồn gốc hạt Arabica.") do |c|
  c.campaign = campaign
end

AuditLog.record!(org: org, user: users[:owner], action: "demo.seeded")

puts "Done. Đăng nhập: owner@demo.vn / password123"
