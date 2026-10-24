# Phase 1 — Hoàn thiện nền đã có (không cần credentials)

Ngày: 2026-08-17. Trạng thái: **133/133 RSpec pass** (87 cũ + 46 mới),
smoke test HTTP 38 lượt tải trang ở cả `vi` và `en` — 0 lỗi, 0 `translation missing`.

Phase 1 làm những hạng mục **không phụ thuộc credentials bên ngoài**. Email thật,
AI provider thật, dịch/gen ảnh thật vẫn thuộc Phase 2–3 (xem cuối tài liệu).

---

## 1. Đa ngôn ngữ (vi/en) — hoàn tất

**Trước:** khung locale chạy được nhưng toàn bộ chữ trên giao diện viết cứng
tiếng Việt; bật `?locale=en` gần như không đổi gì.

**Sau:**
- Toàn bộ 17 view chính đã tách sang key i18n. Kiểm tra tự động không còn chuỗi
  tiếng Việt cứng nào trong `app/views` (trừ 1 dương tính giả là ký tự `›`).
- `config/locales/vi.yml` và `en.yml` đầy đủ, cùng cấu trúc, khoảng 300 key.
- **Ngôn ngữ theo người dùng**: cột `users.locale`; thứ tự ưu tiên là
  `params[:locale]` hợp lệ → tùy chọn đã lưu → mặc định `vi`. Whitelist
  `User::LOCALES` chặn giá trị lạ ở cả controller lẫn model.
- **Nút đổi ngôn ngữ** trên thanh trên cùng: lưu tùy chọn thật rồi quay lại đúng
  trang đang xem (`return_to`), nên điều hướng tiếp vẫn giữ ngôn ngữ đã chọn.
  `return_to` chỉ nhận đường dẫn nội bộ — chặn open redirect (có test).
- `<html lang>` theo locale hiện tại.

**Việc dịch nội dung nghiệp vụ** (kịch bản, brief của khách) vẫn là chức năng
riêng qua `Translations::CreateService` — không liên quan i18n giao diện.

---

## 2. Cài đặt cá nhân + nhắc nhở theo cấu hình

**Trang mới `/settings`** (mọi role, kể cả client — chỉ sửa được chính mình):

| Tùy chọn | Giá trị |
|---|---|
| Ngôn ngữ giao diện | vi / en |
| Nhắc trước | 15p, 30p, 1h, 3h, 12h, 1 ngày, 2 ngày |
| Kênh nhắc | Trong ứng dụng / Trong ứng dụng + Email |

**Thay đổi trong lịch nhắc:**
- `Reminders::ScheduleForTask` viết lại: mốc nhắc tính theo `reminder_lead_minutes`
  của **người được giao việc** thay vì cứng 1 ngày; kênh theo `reminder_channel`.
- `Reminders::ScheduleForEvent` (mới): nhắc sự kiện cho từng người tham dự theo
  lead time **riêng của họ** — hai người dự cùng cuộc họp có thể được nhắc ở hai
  thời điểm khác nhau. Gọi khi mời attendee và khi RSVP.
- `Reminders::Resync` (mới): đổi cài đặt → dựng lại lịch nhắc cho task/event còn
  hiệu lực của **chính user đó**, không đụng lịch của người khác (có test).
- `Reminder.cancel_stale!` (mới): đổi hạn hoặc đổi lead time thì key cũ bị hủy,
  key mới được tạo — không gửi trùng, không gửi theo mốc đã lỗi thời.
- Kênh email: `ReminderMailer` enqueue thư giao dịch; in-app notification **luôn**
  được tạo dù chọn kênh nào. Dev vẫn là adapter `:test` — chưa gửi thật.

### Bug đã sửa trong lúc làm

**`LIKE` không có mệnh đề `ESCAPE`.** `sanitize_sql_like` escape `_` thành `\_`,
nhưng SQLite/Postgres không hiểu backslash là ký tự escape nếu không khai báo
`ESCAPE '\'`. Hệ quả: `cancel_stale!` **không khớp bản ghi nào** — reminder cũ
không bao giờ bị hủy, người dùng sẽ nhận nhắc trùng theo mốc cũ. Ba test phát
hiện, đã sửa và khóa lại bằng regression test.

---

## 3. Thư viện template

**Trang `/templates` viết lại** thành ba khu vực dữ liệu thật:

1. **Mẫu quy trình campaign** (`ProjectTemplate`) — kèm form "Dùng mẫu" ngay tại chỗ.
2. **Prompt mẫu** (`PromptTemplate`) — nhóm theo loại nội dung.
3. **Nội dung được đánh dấu mẫu** (artifact).

**CRUD prompt template** (`/prompt_templates`): tạo/sửa/xóa, 13 loại nội dung,
whitelist category, scope theo organization. Sửa phần **hướng dẫn** thì tự tăng
version (sửa tên thì không) — để audit ghi đúng phiên bản prompt đã dùng.

**Prompt template được dùng thật trong workflow AI**, không còn là bảng chết:
- Chọn prompt mẫu ngay trong khối "Nháp kịch bản" ở trang campaign.
- `ScriptDraft.build_prompt` chèn `instructions` + `output_format` của mẫu vào
  giữa prompt. **Ràng buộc "không bịa số liệu" luôn nằm sau khối template** —
  mẫu do người dùng viết không ghi đè được invariant decline-not-hallucinate
  (có test kiểm tra thứ tự này).
- `AiRun.prompt_template_version` và `ai_metadata` ghi lại mẫu đã dùng.
- Mẫu của tổ chức khác bị bỏ qua (resolve trong org, id lạ → nil).

**Lưu campaign thành mẫu** (`Campaigns::SaveAsTemplate`): đóng gói milestone,
task và artifact **đã duyệt** thành `ProjectTemplate`. Ngày lưu dạng `offset_days`
so với ngày bắt đầu nên áp được cho campaign mới bất kỳ.

**Tạo campaign từ mẫu** giờ clone cả artifact mẫu — luôn về trạng thái `draft`,
không kế thừa `approved`, và ghi `source_note` trỏ về mẫu gốc.

**8 prompt mẫu chuẩn marketing** trong seeds: brief tiếp nhận yêu cầu, chân dung
khách hàng, kịch bản video 30 giây, bài mạng xã hội, email marketing, nội dung
quảng cáo, kịch bản chạy sự kiện, prompt tạo ảnh.

---

## 4. CRM — hồ sơ khách hàng

**Trang mới `/clients/:id`** gộp mọi thứ về một khách hàng:
- Thông tin liên hệ (người liên hệ, email, điện thoại — cột mới, có validate email).
- Danh sách campaign kèm tiến độ và người phụ trách.
- **Góp ý từ phía khách**: bình luận của người được mời vào campaign của khách đó.
- **Quyết định duyệt** của họ (duyệt / yêu cầu sửa / từ chối) kèm phiên bản.
- Sự kiện liên quan.

Scope chặt: chỉ lấy comment/decision của collaborator thuộc **chính các campaign
của khách hàng này** — có test chứng minh không lẫn dữ liệu khách khác, không
xem được khách của tổ chức khác, client không vào được CRM.

---

## 5. Lịch nội dung (content calendar)

**`/calendar` viết lại** thành lịch tháng thật, gộp ba nguồn dữ liệu:

| Loại | Nguồn | Màu |
|---|---|---|
| Sự kiện | `events.starts_at` | tím |
| Việc đến hạn | `tasks.due_date` | xanh ngọc |
| Nội dung dự kiến đăng | `artifacts.due_date` | vàng |
| Quá hạn | task chưa xong, quá hạn | đỏ |

- Chuyển tháng tới/lui, nút "Hôm nay"; tham số tháng sai định dạng rơi về tháng
  hiện tại thay vì raise (có test với `month=hack; DROP TABLE` và `2026-99`).
- Scope qua `Access::CampaignAccessScope` — không hiện dữ liệu campaign ngoài
  phạm vi truy cập (có test).
- Ô lịch hiện tối đa 4 mục, còn lại gom thành "+N nữa".

---

## Bug khác đã sửa (phát hiện khi tách i18n)

1. **Nút lọc task hỏng.** Code cũ `[["", "Tất cả"], ["mine", ...]].each do |f, label|`
   rồi dùng `f[0]` — `f` đã là chuỗi, nên `f[0]` lấy **ký tự đầu** (`"overdue"` → `"o"`).
   Mọi nút lọc trừ "Tất cả" gửi sai tham số nên không lọc được gì. Đã sửa.
2. **HTML lồng sai ở khối "Rủi ro duyệt"** trong campaign show: một `<div>` nằm
   trong `<span>` và thiếu thẻ đóng. Đã tách thành hai khối `kv` hợp lệ.
3. **Biến `t` che helper `t()`** trong vòng lặp task — Ruby vẫn phân giải đúng
   nhưng rất dễ gây nhầm khi đọc; đã đổi tên biến thành `task`.

---

## Test mới (46 ví dụ)

| File | Nội dung |
|---|---|
| `spec/requests/phase1_user_settings_spec.rb` | ngôn ngữ theo user, whitelist, open redirect, chỉ sửa được chính mình |
| `spec/requests/phase1_templates_spec.rb` | CRUD prompt template, phân quyền, cross-tenant, lưu campaign thành mẫu, clone artifact |
| `spec/requests/phase1_calendar_crm_spec.rb` | lịch tháng gộp 3 nguồn, chuyển tháng, tham số lỗi, scope; hồ sơ khách hàng |
| `spec/services/phase1_reminders_spec.rb` | lead time cá nhân, hủy lịch cũ, idempotent, kênh email, resync |
| `spec/services/phase1_prompt_template_ai_spec.rb` | prompt mẫu chèn vào workflow, invariant không bị ghi đè, chỉ lưu hash |

`spec/rails_helper.rb` bổ sung `ActiveSupport::Testing::TimeHelpers` và
`ActiveJob::TestHelper`.

---

## Migration

`20260817050000_add_user_prefs_and_client_contacts.rb`:
`users.locale`, `users.reminder_lead_minutes` (mặc định 1440),
`users.reminder_channel` (mặc định `in_app`),
`clients.contact_name`, `clients.contact_email`, `clients.contact_phone`.

---

## Vẫn còn là mock — cần credentials (Phase 2–3)

Không có gì trong Phase 1 làm thay đổi các giới hạn đã ghi ở
`IMPLEMENTATION_REPORT.md`:

- **Email**: adapter `:test` — soạn thư và enqueue đúng, nhưng **không gửi thật**.
  Cần SMTP/Resend qua ENV (Phase 2).
- **AI**: provider `fake` mặc định, offline deterministic. Prompt mẫu đã được nối
  vào workflow nên khi bật provider thật là dùng được ngay (Phase 3).
- **Dịch**: vẫn là từ điển cứng vi→en. Dịch bằng LLM và dịch nhanh realtime ở Phase 3.
- **Gen ảnh**: vẫn chỉ tạo prompt package, không render ảnh (Phase 3).
- **Reminder chạy định kỳ**: cần Solid Queue worker (`bin/jobs`) hoặc cron gọi
  `ReminderDispatchJob`; `config/recurring.yml` đã khai báo mỗi 30 phút.
