# Prompt thực thi tiếp cho ZCode

> Sao chép toàn bộ khối prompt bên dưới vào ZCode khi đang mở thư mục `E:\marketing-agentic-platform`.

```text
Bạn là Principal Rails Product Engineer, Security Engineer và Product Designer. Hãy TIẾP TỤC IMPLEMENT trực tiếp trong project hiện có tại:

E:\marketing-agentic-platform

Mục tiêu: biến code Rails MVP hiện tại thành một Marketing Agentic Campaign Workspace dùng được cho đội marketing và khách hàng, theo đúng thiết kế/thành phần trong các tài liệu sau:

1. E:\marketing-agentic-platform\docs\design\marketingos-campaign-workspace-reference.png
2. E:\marketing-agentic-platform\docs\design\campaign-workspace-implementation-brief.md

QUY TẮC LÀM VIỆC BẮT BUỘC

- Đọc toàn bộ source, migrations, routes, specs và hai tài liệu trên trước khi sửa.
- Không chỉ lập kế hoạch hoặc chỉ thay CSS. Hãy implement thật theo từng phase dưới đây.
- Không rewrite dự án từ đầu, không xoá dữ liệu/migration hiện có, không dùng `git reset --hard` hoặc xoá database. Tạo migration mới có thể chạy an toàn.
- Giữ demo seed đang có hoạt động. Nếu cần đổi schema, cập nhật factories, seed và tests tương ứng.
- Tất cả thao tác AI, gửi email, calendar, dịch và image generation phải nằm sau server-side adapter. Không đưa API key vào source, logs, browser, git hoặc file `.env.example` có giá trị thật.
- Tuyệt đối KHÔNG dùng Coding Plan/ZCode key hoặc endpoint Coding Plan làm runtime cho web app. ZCode chỉ là coding assistant. Runtime AI dùng provider adapter và chỉ hoạt động khi workspace owner cấu hình key API hợp lệ riêng.
- Không tự gửi email, đăng bài hay gọi API AI bên ngoài trong môi trường local. Local phải dùng mock/log/preview; production action luôn cần explicit human confirmation, consent và audit log.
- Ưu tiên an toàn, cô lập tenant, test và dữ liệu thật hơn animation. Không hard-code số liệu dashboard.
- Dùng lệnh PowerShell tương thích Windows PowerShell 5.1: chạy từng lệnh, không phụ thuộc vào `&&`.
- Sau MỖI phase: chạy migration/test liên quan, sửa lỗi, rồi báo cáo chính xác file đã đổi, test đã chạy và phần còn lại. Không tuyên bố hoàn tất khi test chưa chạy.

============================================================
PHASE 0 — AUDIT VÀ SỬA P0 TRƯỚC MỌI UI
============================================================

1. Sửa authorization thật sự chặn action.
   - `require_role!` hiện redirect nhưng action vẫn có thể tiếp tục. Đổi sang cơ chế fail-closed: return boolean + `return unless`, hoặc exception/rescue/before_action phù hợp Rails.
   - Rà soát mọi read/write/export ở Campaigns, Artifacts, Tasks, Approvals, Comments, Events, Clients, Members, Invitations.
   - Direct request của viewer/client/approver không đủ quyền phải trả 403/redirect an toàn VÀ không thay đổi database.

2. Sửa tenant isolation ở cả controller, model và database.
   - Không nhận raw `client_id`, `artifact_id`, `assignee_id`, `collaborator_id`, `approval_id` từ params rồi find global.
   - Luôn scope từ `current_organization`, campaign hiện tại hoặc quan hệ cha hợp lệ.
   - Campaign phải validate `client.organization_id == campaign.organization_id`.
   - Assignee phải là member cùng organization; artifact/comment/approval/event phải thuộc đúng campaign và organization.
   - Thêm foreign keys, indexes và validation phù hợp; tránh cross-tenant record bằng crafted HTTP request.

3. Bổ sung request specs/end-to-end specs tối thiểu cho:
   - unauthorized direct POST/PATCH/DELETE không ghi dữ liệu;
   - cross-organization client/artifact/assignee không truy cập hay liên kết được;
   - client chỉ xem campaign đã được cấp collaborator access;
   - approver chỉ quyết định approval request được chỉ định.

Definition of done Phase 0:
- Test P0 xanh; migration chạy được trên database demo; không có guard chỉ redirect rồi tiếp tục mutate.

============================================================
PHASE 1 — DATA MODEL CHO QUY TRÌNH MARKETING THẬT
============================================================

Thiết kế và implement migration/model/service tối thiểu sau. Dùng tên rõ ràng, validation/state machine rõ ràng và tất cả records đều scoped organization/campaign.

1. Campaign lifecycle & progress
   - Lifecycle: `brief`, `strategy`, `content_scripts`, `review`, `launch`, `report`.
   - State: `not_started`, `in_progress`, `blocked`, `ready_for_review`, `completed`.
   - Milestone/dependency/blocker; progress phải được tính từ task/milestone thật, không hard-code.

2. Scripts & templates
   - Artifact/script types: campaign brief, social post, video script, event run-of-show, email, landing page, ad copy, storyboard, image prompt.
   - Versioned artifacts; threaded comments theo artifact/version (sẵn sàng mở rộng comment theo block/đoạn).
   - PromptTemplate và ProjectTemplate: category, input schema, instructions, output format, locale, owner/shared flag, version, usage/audit metadata.
   - Cho phép tạo campaign từ ProjectTemplate mà không sửa template gốc.

3. Review/approval
   - ApprovalRequest/ApprovalRound/ApprovalDecision gồm artifact version, người yêu cầu, assigned reviewers, due date, status, quorum và comment.
   - Chỉ reviewer được chỉ định mới quyết định; một reviewer chỉ có một decision cho một round;
   - `approved`, `changes_requested`, `rejected`, `expired`, `cancelled` là state rõ ràng, không ghi đè vô điều kiện bởi quyết định mới.
   - Mời reviewer qua token ký, expiry, revoke, campaign/artifact scope; không cấp toàn bộ CRM/campaign cho guest.

4. Work, meeting & reminder
   - Task: priority, owner, due_at, dependency/blocker, linked artifact/milestone, status.
   - Reminder: người nhận, schedule, timezone workspace, channel, trạng thái queued/sent/cancelled/failed và audit log.
   - Meeting/Event: attendees, RSVP, agenda, meeting link, reminders, ICS export. Chưa cần OAuth calendar thực nếu chưa có credential, nhưng tạo CalendarProviderAdapter interface và mock adapter.

5. Client & guest access
   - ClientContact/GuestAccess hoặc mô hình tương đương; mời qua email đã được owner nhập/có quyền gửi.
   - Client chỉ thấy campaign/artifact/approval mà họ được cấp, không thấy client list hay campaign khác.

6. AI audit/consent
   - AiRun lưu provider/model, workflow/prompt template version, input references (không lưu raw sensitive data nếu không cần), output artifact, initiator, timestamp, consent status, human-review status và error metadata đã redacted.
   - Chỉ owner/admin được bật external AI cho workspace; editor chỉ có thể yêu cầu, không tự cấp consent gửi dữ liệu khách hàng ra ngoài.

Definition of done Phase 1:
- Migrations có foreign keys/indexes; model specs cover state/validation; demo seed có một campaign với tasks, scripts, review và meeting thật.

============================================================
PHASE 2 — XÂY UI CAMPAIGN WORKSPACE THEO MOCKUP
============================================================

Implement visual hierarchy từ `marketingos-campaign-workspace-reference.png`; dùng brief làm chuẩn hành vi.

1. App shell
   - Desktop sidebar: Overview, Campaigns, Content Studio, Calendar, Clients, Templates, Settings.
   - Topbar có search, notification, profile; responsive collapse tại <= 1024px.
   - Không dùng Tailwind CDN trong production. Thiết lập asset/CSS build cục bộ hoặc design tokens CSS có version control.
   - Dùng design tokens: navy/indigo/teal/amber, nền off-white, card radius 16px, spacing 4/8/12/16/24/32.

2. Campaign Workspace page
   - Campaign Header: breadcrumb, title, client, owner, dates, status, progress thật, button `Mời người duyệt`.
   - Lifecycle rail: Brief → Strategy → Content & Scripts → Review → Launch → Report; click dẫn tới dữ liệu thật.
   - Main column: Priority Tasks, Pending Approvals, recent feedback.
   - Right column: AI Campaign Copilot, upcoming meeting, campaign health.
   - Các card có loading, empty, error state; dashboard metrics lấy từ query/service, không `.size` trên collection đã limit.

3. Các màn hình liên quan
   - Script/Artifact editor + version history + comment thread + send for review.
   - Approval detail với reviewer list, deadline, decision/comment và audit trail.
   - Template library, tạo project từ template, form campaign intake/brief.
   - My Work / Calendar / Client portal scoped theo role.
   - Mobile <=768px: header xếp dọc, lifecycle cuộn ngang, sidebar collapse, task/approval hiển thị đủ thao tác.

4. Accessibility / UX
   - Semantic HTML, focus state, label cho icon button, màu trạng thái có text/icon (không chỉ màu), thông báo thành công/lỗi rõ ràng.
   - Dùng icon SVG nhất quán, không dùng emoji thay action nghiệp vụ.
   - Tất cả UI copy qua I18n, không hard-code tiếng Việt trong view.

Definition of done Phase 2:
- Screenshot desktop và mobile khớp hierarchy mockup; owner/manager/editor/approver/client xem đúng dữ liệu và đúng CTA.

============================================================
PHASE 3 — MARKETING WORKFLOWS, ĐA NGÔN NGỮ VÀ AI ADAPTERS
============================================================

1. Internationalization
   - Thiết lập `vi` mặc định và `en` ít nhất; locale switcher; timezone workspace `Asia/Ho_Chi_Minh` mặc định có thể cấu hình.
   - Không trộn string tiếng Việt cứng trong view; thêm locale specs cơ bản.

2. Content workflow chuẩn
   - Intake → survey/research summary → audience segmentation → persona → insight/message house → channel strategy → outline → draft → review → approved/publish-ready.
   - Mỗi bước có template/prompt, required inputs, output structure, owner và approval gate.
   - Không tự publish/post; output AI phải được human review và mang nhãn AI-assisted khi phù hợp.

3. Translation
   - Tạo TranslationProviderAdapter và TranslationJob; UI cho source/target locale, glossary/brand voice, review state và side-by-side diff.
   - Có thể dùng CDFL harness ở `D:/CDFL harness` như safety/orchestration layer nếu integration tương thích; không giả định CDFL tự là dịch vụ model. Khi chưa có provider key, dùng deterministic mock/local preview rõ ràng.

4. Image generation
   - Tạo ImageGenerationProviderAdapter + job + prompt template library cho campaign visual/social/event assets.
   - Input gồm brand, objective, audience, channel, dimensions, style, exclusions, licensing/source notes; output cần approval trước export/use.
   - Local mock/placeholder nếu chưa có provider; không nhúng secret ở client.

5. Email, notification, calendar
   - Email adapter (development: preview/log; production: provider do owner cấu hình) cho invite reviewer, approval requested, comment mention, meeting invite, reminder.
   - Mỗi external email phải có preview, recipient list, consent/authorization, audit log; không bulk send mặc định.
   - Implement background jobs/retry/idempotency và scheduled reminder có timezone; test mailer/job bằng adapter fake.

Definition of done Phase 3:
- Có demo end-to-end: tạo campaign từ template → lập brief → sinh script draft (mock nếu no key) → mời reviewer → feedback → approval → task/reminder/meeting → client chỉ theo dõi đúng scope.

============================================================
PHASE 4 — QUALITY GATE, RUN VÀ BÀN GIAO
============================================================

1. Chạy và sửa cho đến khi pass:
   - `bundle exec rails db:migrate`
   - `bundle exec rails db:seed`
   - `bundle exec rspec` (hoặc test suite tương đương project)
   - Smoke test các routes chính bằng role owner, editor, approver, client.

2. Kiểm tra deployment readiness:
   - Không dependency đường dẫn Windows tuyệt đối trong Docker/Linux production; đóng gói/ghi rõ cách cài CDFL harness an toàn.
   - Chọn cấu hình database production nhất quán (Postgres nếu deploy multi-user), không mô tả Docker/Postgres nhưng chạy SQLite trái ngược.
   - `.env.example` chỉ có tên biến; không secret; health checks và error logging an toàn.

3. Khi hoàn tất, tạo `docs/IMPLEMENTATION_REPORT.md` gồm:
   - Chức năng đã làm theo từng phase;
   - migrations/models/controllers/views/services đã thêm/sửa;
   - security fixes và các request specs chứng minh;
   - cách chạy local trong PowerShell;
   - biến môi trường cần thiết, tất cả optional/mocked mặc định;
   - screenshot desktop/mobile của Campaign Workspace;
   - những integration cần credentials/quyết định kinh doanh trước production.

KHÔNG KẾT THÚC bằng một kế hoạch suông. Bắt đầu Phase 0 ngay, implement, test, rồi tiếp tục tuần tự cho đến khi hoàn thành các phase có thể làm được local. Chỉ dừng để hỏi khi bị thiếu quyền truy cập, credential bắt buộc hoặc một quyết định nghiệp vụ không thể suy luận an toàn.
```
