# Prompt: phát triển chức năng từ Campaign Workspace

> Dán nguyên khối dưới đây vào ZCode sau prompt UI. Đây là prompt để biến các card/màn hình thành chức năng marketing thật, không chỉ giao diện.

```text
TIẾP TỤC IMPLEMENT project Rails ở E:\marketing-agentic-platform.

Bạn vừa/đang làm UI Campaign Workspace. Bây giờ hãy phát triển TOÀN BỘ chức năng nằm sau UI đó. Hãy xem các file sau là product specification bắt buộc:

1. E:\marketing-agentic-platform\docs\design\marketingos-campaign-workspace-reference.png
2. E:\marketing-agentic-platform\docs\design\campaign-workspace-implementation-brief.md
3. E:\marketing-agentic-platform\docs\design\zcode-ui-implementation-prompt-vi.md

Mục tiêu sản phẩm: một Marketing Operations Workspace để agency/đội nội bộ/khách hàng cùng lập brief, tạo kịch bản và content, góp ý, duyệt, theo dõi công việc/lịch/hạn, tái sử dụng template, và dùng AI có kiểm soát. Mọi UI card phải có dữ liệu và hành động nghiệp vụ thật ở phía sau.

NGUYÊN TẮC BẮT BUỘC

- Không chỉ giải thích hoặc tạo TODO. Hãy implement code, migrations, routes, services, views/components, seeds và tests theo từng phase.
- Không rewrite/xóa database hay seed hiện có. Chỉ tạo migration additive/an toàn và update code tương ứng.
- Sửa P0 phân quyền/cô lập tenant trước khi mở rộng bất kỳ chức năng nào. Không tin ID từ params: scope mọi record từ organization/campaign/parent record hiện tại.
- Không tự gửi email, post social, hoặc gọi provider AI/image/translation từ local. Dùng server-side adapters, local fake/preview, human confirmation, consent và audit log.
- Không dùng Coding Plan/ZCode key/end-point làm runtime. ZCode chỉ là coding assistant; runtime provider dùng key API hợp lệ do owner tự cấu hình.
- Mọi màn hình có loading/empty/error state, permission gate và I18n (`vi` mặc định, `en` tối thiểu). Không hard-code string UI mới trong view.
- Sau mỗi phase: chạy migration, seed (idempotent), test liên quan và smoke test theo owner + client/approver. Sửa lỗi rồi mới đi tiếp.

================================================================
PHASE 0 — SECURITY FOUNDATION (LÀM TRƯỚC)
================================================================

1. Authorization fail-closed
   - Sửa `require_role!`/policy để redirect/forbidden dừng hẳn action, không để mutation tiếp tục sau redirect.
   - Áp dụng cho Campaigns, Artifacts, Tasks, Approvals, Comments, Events, Clients, Members và invitations.

2. Tenant isolation
   - `client_id`, `artifact_id`, `assignee_id`, `campaign_id`, `approval_id`, collaborator, event, comment: tất cả được find từ quan hệ đã scope, không global find.
   - Validation/database constraints: campaign-client cùng organization; assignee là member cùng organization; artifact/comment/approval/task/event cùng campaign/organization.
   - Client/guest không bao giờ truy cập CRM, template hoặc campaign ngoài phạm vi được mời.

3. Test P0
   - Request specs chứng minh direct URL/POST/PATCH/DELETE của viewer/client/approver không đổi database nếu không đủ quyền.
   - Test cross-organization reference không thể tạo hoặc đọc.

================================================================
PHASE 1 — CAMPAIGN, BRIEF VÀ TIẾN ĐỘ (HEADER + LIFECYCLE)
================================================================

Biến Campaign Header và Lifecycle Rail thành workflow thật:

- Campaign có objective, audience, channels, dates, owner, budget optional, lifecycle stage và status.
- Lifecycle: Brief → Strategy → Content & Scripts → Review → Launch → Report.
- State mỗi stage: not_started, in_progress, blocked, ready_for_review, completed.
- Milestone có owner, due_at, dependency, blocker/reason; progress tính từ tasks/milestones thật.
- Campaign intake/brief form có các phần: business goal, product/service, audience, insight, message, channels, success metrics, constraints, brand voice, required assets.
- Header hiển thị progress, owner, dates và trạng thái lấy từ model/service; click lifecycle step đi đến section/route đúng.
- `Campaign Health` lấy deadline risk, blocked work, review risk, workload/budget từ dữ liệu thật và dẫn đến item gốc.

Definition of done: tạo/sửa campaign, đổi lifecycle state hợp lệ, thấy progress/health chính xác trong Campaign Workspace.

================================================================
PHASE 2 — CONTENT STUDIO, KỊCH BẢN VÀ TEMPLATE
================================================================

Biến `Content Studio`, `Tạo nội dung` và artifact cards thành module làm việc thật:

- Artifact/script types: campaign brief, social post, video script, event run-of-show, email, landing-page copy, ad copy, storyboard, image prompt, report.
- Versioned artifact: draft → in_review → changes_requested → approved/rejected → archived; không overwrite nội dung được duyệt.
- Editor có title, type, rich/plain content an toàn, locale, brand voice, channel, target persona, due date, source/AI disclosure fields.
- Version history và restore/duplicate tạo version mới, không phá audit history.
- Threaded feedback theo artifact/version; chuẩn bị schema cho block/section comment, tối thiểu comment theo artifact/version ngay bây giờ.
- PromptTemplate: category, input schema, instructions, output format, locale, version, owner/shared flag. ProjectTemplate: bundle lifecycle/milestones/artifact templates/task defaults.
- Tạo campaign từ ProjectTemplate phải clone cấu hình vào campaign, không mutate template gốc.
- Cung cấp seed templates hữu ích: Social campaign, Video launch, Event, Email launch, Content calendar.

Definition of done: owner tạo campaign từ template, tạo script type, sửa/version, comment và gửi duyệt được; Content Studio có dữ liệu thật.

================================================================
PHASE 3 — COLLABORATION, REVIEW VÀ CLIENT PORTAL
================================================================

Biến `Đang chờ duyệt`, feedback cards và CTA `Mời người duyệt` thành luồng an toàn:

- Tạo ApprovalRequest/ApprovalRound/ApprovalDecision với artifact version, requester, assigned reviewers, due date, status, quorum optional và comment.
- Một reviewer chỉ có một decision trên một approval round; quyết định mới không được ghi đè quyết định cũ hoặc artifact status tùy ý.
- State rõ: pending, approved, changes_requested, rejected, expired, cancelled. Chỉ allowed transition mới chạy.
- Dialog `Mời người duyệt`: email, role, scope campaign/artifact, expiry, revoke, preview email. Gửi qua adapter ở local chỉ log/preview.
- Signed token invite, audit trail và revoke; người nhận chỉ thấy artifact/campaign được cấp.
- Client portal: `My campaigns`, artifact shared, approval/comment/progress được phép; tuyệt đối không thấy Clients index, campaign khác, member list/setting nội bộ.
- Notification in-app cho mention, review requested, changes requested, due soon; mở đúng record.

Definition of done: demo có owner gửi một script version cho approver/client, nhận feedback, request changes, version mới và approve; từng role thấy đúng scope.

================================================================
PHASE 4 — TASKS, LỊCH, MEETING VÀ REMINDER
================================================================

Biến `Việc ưu tiên`, `Cuộc họp sắp tới` và notification thành công việc thật:

- Task: title, status, priority, assignee, due_at, dependency/blocker, linked campaign/milestone/artifact, completion audit.
- Filters `Của tôi`, `Quá hạn`, `Đang bị chặn`, `Chờ phản hồi`; deadline/timezone đúng workspace.
- Reminder: recipient, schedule, channel, state queued/sent/failed/cancelled, idempotency key, audit log. Owner/admin tùy chỉnh reminder rules; local chỉ in-app/log.
- Event/Meeting: agenda, location/video link, start/end timezone, attendees, RSVP, attached campaign/artifact, reminder, ICS export.
- Calendar page có danh sách/tuần/tháng phù hợp khả năng hiện có; có `CalendarProviderAdapter` interface và fake adapter. Chỉ thêm Google/Outlook OAuth khi credentials hợp lệ được cung cấp.

Definition of done: task overdue/blocked nổi bật đúng trên Workspace; meeting có attendee/RSVP/ICS; reminder job testable mà không gửi mail thật.

================================================================
PHASE 5 — AI COPILOT, CONTENT WORKFLOW, DỊCH VÀ IMAGE
================================================================

Biến `AI Campaign Copilot` thành trợ lý minh bạch, không phải nút tạo dữ liệu giả:

- Provider adapters: `AiProviderAdapter`, `TranslationProviderAdapter`, `ImageGenerationProviderAdapter`; server side only, fake deterministic default.
- AiRun/audit record: provider/model, workflow, prompt-template version, input record references, initiator, consent status, output artifact, human review, redacted error metadata. Không lưu raw sensitive prompt/output nếu không cần.
- External AI chỉ owner/admin bật workspace-wide; mỗi request hiển thị provider/dữ liệu/mục đích và cần explicit confirmation. Editor có thể request, không tự cấp consent.
- Content workflow: Intake → research/survey summary → audience segment → persona → insight/message house → channel strategy → outline → draft → human review → approved/publish-ready.
- Mỗi bước có structured input/output, template/prompt, source references, owner, status và approval gate.
- Translation UI: source/target locale, glossary/brand voice, side-by-side result, reviewer state. `vi` + `en` tối thiểu; thêm kiến trúc cho ngôn ngữ khác.
- Image studio: form brand/objective/audience/channel/dimensions/style/exclusions; prompt templates; generated asset metadata, licensing/source note, approval trước export/use. No real provider call without configured credential.
- AI output mang nhãn AI-assisted/generated và không tự publish/post/email.

Definition of done: demo chạy full flow với Fake adapter: tạo brief → persona → outline/script → review → approval; translation/image UI chạy mock rõ ràng, không gọi mạng.

================================================================
PHASE 6 — EMAIL, PRODUCTION READINESS VÀ QUALITY GATE
================================================================

- Email adapter cho review invite, approval requested, mention, meeting invite/reminder. Dev: preview/log; production: provider setup do owner quản lý; recipient preview + explicit send confirmation + unsubscribe/notification settings khi phù hợp.
- Background jobs retry/idempotency/error states; không gửi bulk mặc định.
- I18n toàn bộ copy UI mới; timezone workspace configurable, default `Asia/Ho_Chi_Minh`.
- Không dependency đường dẫn Windows tuyệt đối trong Docker/Linux production. Làm rõ cách cài CDFL harness hoặc package/gem substitute; không tuyên bố Docker/Postgres nếu compose thực tế không chạy được.
- Test: model/service/request/system cho RBAC, tenant isolation, approval state machine, invitation scope, reminders/jobs, AI fake adapter, locale, UI smoke test.
- Tạo `docs/IMPLEMENTATION_REPORT.md`: file/migration đã thay đổi, commands test đã pass, screenshots desktop/mobile, variables optional, integration cần credentials trước production.

THỨ TỰ THỰC THI

1. Làm Phase 0 hoàn chỉnh và test.
2. Làm Phase 1 + 2, giữ UI mockup là chuẩn visual.
3. Làm Phase 3 + 4.
4. Làm Phase 5 với fake adapters trước.
5. Làm Phase 6 và báo cáo.

Không kết thúc bằng một plan suông. Hãy bắt đầu sửa code ngay, commit/logical checkpoint theo phase nếu project dùng Git, và khi bị thiếu credential thì implement adapter/mock/UX thay vì bỏ qua toàn bộ module. Chỉ hỏi người dùng khi quyền truy cập, credential bắt buộc hoặc quyết định nghiệp vụ không thể suy luận an toàn.
```
