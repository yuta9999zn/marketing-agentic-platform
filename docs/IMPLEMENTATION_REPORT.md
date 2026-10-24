# MarketingOS — Implementation Report

Cập nhật sau phase "biến UI thành chức năng thật" (Phase 0 → 6 của brief).
Trạng thái: **55/55 RSpec pass**; smoke test HTTP đầy đủ (đăng nhập, round duyệt,
translation, client portal, tạo campaign từ template).

## Phase 0 — Security foundation

- `require_role!` fail-closed: trả boolean, mọi caller dùng `return unless` —
  request bị từ chối dừng hẳn, không mutate. Áp dụng cho Campaigns, Artifacts,
  Tasks, Approvals, Comments, Events, Clients, Members, Templates, Studio, Calendar.
- `require_internal!`: client/guest không truy cập CRM (clients), templates,
  content studio qua URL trực tiếp.
- Tenant isolation: mọi id từ params được resolve trong scope organization
  (client_id, assignee_id, artifact_id, campaign_id, round_id, collaborator);
  model validation: campaign↔client cùng org, task assignee là member org,
  task dependency cùng campaign, comment artifact cùng campaign.
- Specs: `spec/requests/authorization_p0_spec.rb`, `spec/requests/client_portal_spec.rb`.

## Phase 1 — Campaign, brief, tiến độ

- Migration: campaigns thêm audience, channels, budget, brief_data (10 section
  intake), owner_id, lifecycle_stage; bảng milestones (state, due_at, owner,
  position); tasks thêm milestone_id, depends_on_id.
- Progress tính từ tasks + milestones thật (fallback artifact approved ratio);
  header hiển thị owner/budget; Campaign Health có milestone states, overdue,
  review risk, ngân sách thật (không hard-code).
- Form campaign mới: intake đầy đủ section + chọn từ ProjectTemplate.

## Phase 2 — Content Studio & templates

- Artifact kinds mở rộng: social_post, video_script, event_run_of_show, email,
  landing_page, ad_copy, storyboard, report, translation.
- State machine: `draft → in_review → approved|changes_requested|rejected → archived`
  (validation `transition_allowed` theo `approval_status_was`); `withdraw!` rút
  về draft + hủy round; edit luôn tạo version mới — nội dung đã duyệt nằm nguyên
  trong artifact_versions; `restore_version!`, `duplicate!`.
- Editor thêm locale, channel, due_date, source_note.
- `PromptTemplate` + `ProjectTemplate`; tạo campaign từ template qua
  `Campaigns::CreateFromTemplate` (clone milestones/tasks, không mutate template).
  Seeds 5 templates: Social Campaign, Video Launch, Event, Email Launch, Content Calendar.
- Content Studio liệt kê artifact thật theo updated_at + đếm chờ duyệt.

## Phase 3 — Review/approval & client portal

- `ApprovalRound` (artifact_version, requester, reviewer_ids, due_date, quorum,
  status) + `ApprovalDecision` (unique index round+user — một reviewer một decision).
- `Approvals::Submit` / `Approvals::Decide`: chỉ reviewer được chỉ định quyết định;
  rejected/changes_requested terminal; không quorum → cần tất cả reviewer approve,
  có quorum → đủ số lượt; artifact status chỉ sync từ round MỚI NHẤT đã kết thúc.
- Trang artifact: form gửi duyệt (chọn reviewers + hạn + quorum), card quyết định,
  lịch sử vòng duyệt kèm decisions, nút rút/duyệt/khôi phục/nhân bản/dịch.
- Collaborator UI trong campaign (cấp/thu hồi quyền view/comment); dialog mời
  người duyệt (workspace invite + hướng dẫn scope).
- Client portal: client chỉ thấy campaign được mời (test trực tiếp 200/302).

## Phase 4 — Tasks, lịch, reminder

- Task filters trên workspace: Tất cả / Của tôi / Quá hạn / Bị chặn / Chờ phản hồi
  (scope thật theo query param).
- `Reminder` + `Reminders::DispatchDueService` + `ReminderDispatchJob`: idempotency
  key unique, lock + state machine — chạy lại không gửi trùng; local chỉ tạo
  in-app notification (không mail thật).
- `EventAttendee` + RSVP (yes/no/maybe) + ICS kèm ATTENDEE lines; mời attendee
  từ UI; `CalendarProviderAdapter` + `CalendarFakeAdapter` (ICS/push mock) —
  Google/Outlook OAuth chỉ khi có credential.

## Phase 5 — AI copilot, dịch, image

- `AiRun` audit mức workflow (provider, model, consent, input refs, output
  artifact, human_review) — ghi bởi mọi workflow; `ai_calls` giữ audit mức
  gateway (chỉ hash).
- Triple-gate AI ngoài: ENV `AI_EXTERNAL_ENABLED` + org setting
  (`organizations.ai_external_enabled`, chỉ owner/admin bật ở UI Settings) +
  consent từng lần gọi. Mặc định fake offline.
- `ScriptDraft` workflow: nháp social_post/video_script/email/ad_copy/... từ
  brief+persona, khai báo missing_data thay vì bịa.
- `TranslationProviderAdapter` + FakeAdapter (glossary vi→en deterministic,
  output là BẢN NHÁP chờ duyệt); UI nút "Dịch sang EN" trên artifact; metadata
  trỏ về artifact nguồn.
- `ImageGenerationProviderAdapter` + FakeAdapter: image studio form
  (brand/objective/audience/channel/dimensions/style/exclusions) tạo artifact
  image_prompt kèm licensing note + approval-required — KHÔNG render ảnh thật,
  không gọi provider ngoài khi chưa có credential.

## Phase 6 — Production readiness

- I18n: vi mặc định (ghim theo server, không theo Accept-Language), `?locale=en`
  chuyển được; `en.yml` có date/time/nav keys. **Nợ kỹ thuật**: copy UI của các
  view chính vẫn inline tiếng Việt — cần tách key trong lần refactor kế (đã ghi
  trong section "Còn lại").
- Timezone workspace: `WORKSPACE_TIMEZONE` (mặc định Asia/Ho_Chi_Minh).
- Background job reminder testable bằng adapter inline/test.
- ~~Harness `cdfl_harness` tham chiếu path `D:/CDFL harness`~~ — **đã thay** bằng
  `vendor/gems/cdfl_harness` để build được trên Linux (xem `docs/DEPLOY_REPORT.md`).
  Ghi chú cũ: Deploy
  Linux/Docker cần vendor gem hoặc private gem server — xem README.
- Test suite: 55 examples — model (state machine, version, milestone), services
  (approvals, template, reminder, translation), request (P0, client portal,
  approvals flow), AI fake adapter (không mạng).

## Files chính thay đổi (phase này)

- Migrations: `20260816160038_create_platform_functionality.rb`,
  `20260816160810_add_reviewer_ids_to_approval_round.rb`
- Models mới: Milestone, ApprovalRound, ApprovalDecision, PromptTemplate,
  ProjectTemplate, EventAttendee, Reminder, AiRun, CampaignCollaboratorToken
- Models sửa: Campaign (brief_data/owner/progress/milestone), Artifact (state
  machine + fields), Task (milestone/depends_on + validations), Comment, Event
  (attendees/ICS), Organization (AI setting), Approval (legacy, bỏ ghi đè status)
- Services: Campaigns::CreateFromTemplate, Approvals::Submit/Decide,
  Reminders::DispatchDueService, Translations::CreateService,
  Images::CreatePromptService, Providers::* (translation/image/calendar + fake),
  Ai::Workflows::ScriptDraft, AiRun ghi trong 3 workflow cũ
- Controllers: artifacts (submit/withdraw/restore/duplicate/translate),
  approvals (round-based), campaigns (from_template, image_prompt),
  collaborators, event_attendees + events#rsvp, workspace_settings
- Views: artifacts show/edit (rounds UI), campaigns new (intake + template) &
  show (filters, collaborators, image studio, RSVP, milestones), members (AI toggle)
- Seeds: templates + round duyệt thật + attendees/RSVP + reminders + script drafts

## Chạy local (PowerShell)

```powershell
$env:Path = "C:\Ruby33-x64\bin;" + $env:Path
cd E:\marketing-agentic-platform
bundle exec rails db:migrate
bundle exec rails db:seed
bundle exec rails server    # http://localhost:3000 — owner@demo.vn / password123
bundle exec rspec           # 55 examples
```

Hoặc `.\start.ps1`.

## Biến môi trường (đều optional/mocked mặc định)

Xem `.env.example`: `AI_PROVIDER=fake`, `AI_EXTERNAL_ENABLED=false`,
`ANTHROPIC_API_KEY`/`OPENAI_API_KEY`, `OLLAMA_HOST`, `WORKSPACE_TIMEZONE`,
SMTP/Resend cho production email.

## Cần credentials / quyết định kinh doanh trước production

- Email thật (SMTP/Resend), calendar OAuth (Google/Outlook), AI provider thật,
  dịch máy thật, image provider thật — hiện đều là adapter fake/preview an toàn.
- Reminder scheduling chạy thật cần `bin/jobs` (Solid Queue) hoặc cron gọi
  `ReminderDispatchJob`.
- Campaign-scoped reviewer invite token (bảng đã có `campaign_collaborator_tokens`,
  chưa có UI đầy đủ) — hiện dùng workspace invite + collaborator assignment.
- I18n extraction toàn bộ copy UI sang key (vi/en).

## Cập nhật sau remediation audit (2026-08-17)

Xem chi tiết: `docs/REMEDIATION_REPORT.md`. Test suite hiện **87/87 pass**
(gồm 32 regression specs cho mọi bug P0/P1 của audit). Thay đổi chính:

- Dashboard/session fail-closed theo membership; `CampaignAccessScope` là nguồn
  scope duy nhất — client/external_reviewer không thấy gì ngoài campaign được mời.
- Role `external_reviewer` + invite campaign-scoped (token, expiry, revoke,
  acceptance tự tạo membership restricted + collaborator access).
- Approval version integrity: sửa artifact đang duyệt → round cũ tự cancel;
  quyết định trên version cũ bị từ chối; sync chỉ áp cho round khớp version.
- Collaborator DELETE / image prompt POST / task milestone-dependency /
  lifecycle transition đều hoạt động và có test.
- en.yml đầy đủ + locale whitelist vi/en (dashboard không còn 500).
- AI: fake chỉ khi provider fake; adapter factory lỗi rõ ràng khi external
  chưa cấu hình; metadata chỉ lưu prompt_sha.

Phân loại trung thực:
- **Implemented + tested:** toàn bộ Phase 0–5 ở trên + remediation A–F.
- **Offline/mock MVP:** email (test adapter), calendar (fake adapter),
  translation/image (fake deterministic), AI workflows (fake provider mặc định).
- **Requires credential/business decision:** SMTP/Resend, Google/Outlook OAuth,
  AI provider thật, translation/image provider thật, chạy Solid Queue worker
  cho reminder định kỳ.
