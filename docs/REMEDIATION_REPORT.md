# REMEDIATION_REPORT — Audit P0/P1 fix

Ngày: 2026-08-17. Trạng thái: **87/87 RSpec pass** (55 cũ + 32 mới/regression),
smoke test bằng HTTP/runner sau khi **restart server** (config đổi xong mới test).

## Phase A — P0: Client dashboard leakage

**Root cause:** `DashboardController#index` chỉ scope `campaign_scope` cho client ở
query campaigns; task count, approval count, my tasks, week events, audit activity
vẫn query toàn organization.

**Fix:**
- `app/services/access/campaign_access_scope.rb` — scope dùng chung duy nhất:
  internal roles → campaign trong org; client/external_reviewer → chỉ campaign có
  `campaign_collaborators.user_id = current_user.id`.
- `DashboardController#index` viết lại: **mọi** query (count, tasks, approvals,
  attention, events) đi qua `campaign_ids = CampaignAccessScope.ids_for(...)`.
- Audit activity: campaign-scoped role thấy `AuditLog.none` (chưa có scope an toàn).
- View: link Content Studio chỉ render cho internal (`@is_internal`); layout nav
  dùng `campaign_scoped_role?` (client + external_reviewer đều thu hẹp).

**Regression:** `spec/requests/remediation_phase_a_b_spec.rb` — client collaborator
campaign A: `/` trả 200 nhưng KHÔNG chứa tên/task/event/artifact/audit của campaign B;
direct URL B redirect và không leak title trong HTML.

## Phase B — P0: Session/membership fail-closed

**Root cause:** `current_organization` tin `session[:org_id]` bằng global find;
`require_internal!` chỉ chặn đúng role "client", role blank vẫn qua.

**Fix (`app/controllers/concerns/authentication.rb` viết lại):**
- Org chỉ resolve qua `current_user.organizations.find_by(id: session[:org_id])`;
  session cũ không hợp lệ → `session.delete(:org_id)` + fallback org hợp lệ đầu tiên;
  không còn org → `reset_session` + redirect login trong `require_login`.
- `require_internal!` đổi sang **allowlist** `INTERNAL_ROLES` — role blank,
  client, external_reviewer đều bị chặn.
- Thêm `campaign_scoped_role?` helper.

**Regression:** revoked-membership spec — sau khi xóa Membership, `/`, `/clients`,
`/content-studio`, `/calendar`, `/templates`, `/members` đều redirect login, body
không chứa dữ liệu org cũ.

## Phase C — P0: Approval version integrity

**Root cause:** `ArtifactsController#update` cho edit artifact `in_review`;
`new_version!` không hủy round pending của version cũ; `sync_artifact_status`
chỉ so ID round mới nhất (không so version) và dùng `update_column` bỏ validation.

**Fix:**
- `Artifact#new_version!`: nếu đang `in_review` → **atomically cancel mọi round
  pending** của version cũ rồi về draft (UX: sửa = rút bản + mở vòng mới sau).
- `Approvals::Decide`: bọc trong `round.with_lock`; từ chối nếu
  `round.artifact_version != artifact.version` hoặc artifact không còn `in_review`.
- `ApprovalRound#sync_artifact_status`: chỉ sync khi là round **non-cancelled mới
  nhất** VÀ `artifact_version == artifact.version`; bỏ `update_column`, dùng
  `update!` (validation chạy) + rescue khi artifact đã rời trạng thái phù hợp.

**Regression:** `spec/services/remediation_phase_c_spec.rb` — kịch bản audit gốc:
submit v1 → edit v2 → quyết v1 bị từ chối, v2 còn draft, round v1 cancelled;
decide trên round version cũ bị chặn kể cả khi ép round sống; approve v1 hợp lệ
rồi edit → v2 draft, v1 đã duyệt nguyên vẹn trong history.

## Phase D — P0: Campaign-scoped reviewer invite

**Root cause:** dialog "Mời người duyệt" tạo workspace-wide Invitation role
approver → reviewer ngoài xem được TOÀN BỘ campaign org. Role client thì không
duyệt được. Không tồn tại role vừa approve vừa bị giới hạn 1 campaign.

**Fix:**
- Role mới `external_reviewer` (restricted, cap 0 ở org level).
- `CampaignCollaborator::ACCESS = view|comment|approve`; `Policy::ACCESS_CAP`
  map access → permission; client + external_reviewer đều campaign-scoped —
  campaign khác = từ chối toàn bộ, org-level = từ chối toàn bộ.
- Flow invite riêng: `CampaignInvitesController` (create/revoke, chỉ manage
  permission, audit scope campaign) + `CampaignInviteAcceptancesController`
  (token → tạo user nếu mới + membership external_reviewer + collaborator đúng
  access; KHÔNG bao giờ cấp role internal). Mailer preview/log only.
- Dialog campaign show post sang `campaign_campaign_invites_path` với access
  tự chọn; members page giữ workspace invite (internal roles).
- **Table rename:** migration `RenameCampaignCollaboratorsTokensToCampaignCollaboratorTokens`
  (rename_table an toàn, không drop) + spec khóa convention
  `CampaignCollaboratorToken.table_name == "campaign_collaborator_tokens"`.

**Regression:** external reviewer campaign A: xem/duyệt artifact A qua round thật
(POST approvals với session thật), campaign B redirect, 5 route nội bộ 302,
dashboard không leak B; token expired/revoked/accepted đều bị từ chối;
access=comment không approve được; editor không gửi được invite.

## Phase E — P1: Route/action runtime bugs

1. **Collaborator DELETE:** destroy giờ find scoped theo org (`joins(:campaign)
   .where(org)`) rồi authorize manage trên campaign — không cần `campaign_id`.
   Test: revoke xong client mất quyền ngay; cross-org collab không xóa được.
2. **Image Studio POST:** `create_image_prompt` thêm vào `before_action
   :set_campaign`. Test: editor tạo artifact image_prompt (302 → artifact);
   client không mutate.
3. **Task milestone/dependency editable:** strong params + scope đúng campaign
   (id lạ bị clear), model validation milestone cùng campaign + no self-dependency
   + no cycle (A→B→A), UI form thêm 2 select. Test cross-campaign bị clear,
   self-dep/cycle invalid.
4. **Lifecycle:** action `set_lifecycle` (validate stage + manage + audit) + UI
   select trên header. `ProjectTemplate` comment sửa trung thực (artifact_kinds
   KHÔNG clone); `PromptTemplate` ghi rõ là data model chưa expose CRUD UI.

## Phase F — P1: i18n runtime

**Root cause thật:** `config/locales/en.yml` chỉ còn template default "hello"
(file bị revert), cộng thêm locale negotiation theo Accept-Language.

**Fix:** viết lại `en.yml` đầy đủ date/time/nav; `set_locale` whitelist `%w[vi en]`
(param lạ rơi về vi — không bao giờ locale "de" vô hệ thống); server **restart
thật** trước khi smoke.

**Regression + smoke:** `/` (vi, có Accept-Language en) 200; `/?locale=en` 200;
`/?locale=de` 200 với locale fallback vi; dashboard/campaign/artifact render
date/time không raise.

## Phase G — P1: Honest AI/reminder

- `Reminder.schedule` giờ chạy thật khi tạo/cập nhật task có assignee + due_date
  (`Reminders::ScheduleForTask`, idempotent key theo task+due_date);
  `config/recurring.yml` thêm `dispatch_due_reminders` mỗi 30 phút (Solid Queue
  production; dev inline adapter chạy ngay).
- `Ai::Gateway`: scripted fake completion CHỈ được inject khi
  `AI_PROVIDER=fake` — provider thật đã gate đầy đủ thì không bị fake âm thầm thay.
- `Providers::AdapterFactory`: translation/image chọn adapter theo config;
  external được yêu cầu nhưng chưa có adapter thật → raise
  `ExternalNotConfigured` rõ ràng, không gọi mạng, không âm thầm fallback.
- `ai_metadata` không còn lưu raw prompt — chỉ `prompt_sha` (SHA-256); gateway
  `ai_calls` vốn chỉ lưu hash.
- Tests: fake path + external-gate denial + redaction (không network).

## Phase H — Test/report

- Sửa `authorization_p0_spec` POST approvals dùng **round thật** (round_id),
  không phải artifact_id cũ.
- `spec/support/session_helper.rb` — `login_as` đăng nhập QUA ENDPOINT THẬT;
  các security spec mới (A/B/D/E/F) dùng session thật, không stub current_user.
- **Kết quả: `bundle exec rspec` → 87 examples, 0 failures.**

## Manual smoke đã chạy (sau restart server, port 3001)

| Scenario | Kết quả |
|---|---|
| Login owner → `/` vi (kể cả Accept-Language en) | 200 |
| `/?locale=en`, `/?locale=de` | 200, de fallback vi |
| Client login → dashboard | Chỉ thấy "ACME Summer Launch"; "Glow Rebrand" vắng mặt |
| Client → /clients /members /templates /content-studio /calendar | 302 hết |
| Campaign invite reviewer (owner) | 302 → #collaborators, token tạo |
| Image prompt POST (editor) | 302 → artifact image_prompt (400 trước đó là lỗi UTF-8 của Git Bash curl, không phải app — request spec UTF-8 pass) |
| Approval v1/v2: submit v1 → edit v2 | v2 draft, round v1 cancelled, quyết định cũ bị từ chối, artifact còn draft |
| Revoke collaborator + gán lại demo | destroy OK |
| Reminder dispatch | dispatched=1; chạy lại =0 (idempotent) |

## Files/migrations changed

- Migrations: `..._rename_campaign_collaborators_tokens_to_campaign_collaborator_tokens.rb`,
  `..._add_access_to_campaign_collaborator_token.rb`
- Controllers: concern `authentication.rb` (viết lại), `dashboard_controller.rb`
  (viết lại), `campaigns_controller.rb`, `tasks_controller.rb` (viết lại params),
  `artifacts_controller.rb`, `collaborators_controller.rb` (viết lại destroy),
  mới: `campaign_invites_controller.rb`, `campaign_invite_acceptances_controller.rb`,
  `workspace_settings_controller.rb` (không đổi)
- Models: `policy.rb` (viết lại theo access-cap), `artifact.rb`, `approval_round.rb`,
  `task.rb`, `campaign_collaborator.rb`, `campaign_collaborator_token.rb`,
  `organization.rb`, `project_template.rb`, `prompt_template.rb`
- Services: mới `Access::CampaignAccessScope`, `Reminders::ScheduleForTask`,
  `Providers::AdapterFactory`; sửa `Approvals::Decide`, `Ai::Gateway`
- Views: layout (nav scoped), dashboard (gate link), campaign show (dialog invite
  campaign-scoped, lifecycle select, task form milestone/depends_on), en.yml/vi.yml
- Specs: 5 file regression mới + sửa authorization_p0, approvals, client_portal

## Known limits (trung thực)

- Email/calendar/AI/image/translation external: adapter fake/preview — cần
  credentials trước production (xem IMPLEMENTATION_REPORT.md).
- Campaign-scoped invite đã an toàn nhưng chưa có UI list/revoke token trong
  campaign page (revoke có endpoint `POST /campaigns/:id/campaign_invites/:id/revoke`);
 Members page có list invitation workspace.
- Reminder dispatch production cần Solid Queue worker (`bin/jobs`) hoặc cron.
- Copy UI chính vẫn inline tiếng Việt (vi default) — i18n key extraction là việc
  riêng, đã ghi trong IMPLEMENTATION_REPORT.
