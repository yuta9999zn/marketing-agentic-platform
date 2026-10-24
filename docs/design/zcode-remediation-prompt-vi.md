# Prompt sửa lỗi P0/P1 và hoàn thiện chức năng

> Dán toàn bộ khối dưới đây vào ZCode khi đang mở `E:\marketing-agentic-platform`.

```text
Bạn là Principal Rails Security + Product Engineer. Hãy sửa trực tiếp project:

E:\marketing-agentic-platform

KHÔNG được trả lời bằng kế hoạch suông. Hãy đọc code hiện có, implement theo đúng thứ tự bên dưới, tạo migration additive/an toàn, bổ sung regression tests, chạy test và báo cáo bằng chứng. Không `git reset --hard`, không xoá database/seed/demo data, không đổi demo credentials.

TÀI LIỆU THAM CHIẾU

1. E:\marketing-agentic-platform\docs\IMPLEMENTATION_REPORT.md
2. E:\marketing-agentic-platform\docs\design\campaign-workspace-implementation-brief.md
3. E:\marketing-agentic-platform\docs\design\zcode-ui-implementation-prompt-vi.md
4. E:\marketing-agentic-platform\docs\design\zcode-product-functionality-prompt-vi.md

Đây là remediation bắt buộc sau audit độc lập. `55 examples, 0 failures` hiện tại KHÔNG đủ để tuyên bố hoàn tất. Đừng làm feature mới hay chỉ chỉnh CSS trước khi xử lý toàn bộ BLOCKER P0.

============================================================
QUY TẮC AN TOÀN KHÔNG ĐƯỢC VI PHẠM
============================================================

- Mọi read/write phải scope theo organization + campaign/parent record; không `find(params[:id])` global cho dữ liệu nghiệp vụ.
- Nếu user không còn membership của organization hiện tại thì fail closed: không dashboard, CRM, calendar, studio, template hay API action.
- Client và external reviewer chỉ thấy đúng campaign/artifact đã cấp, kể cả dashboard, event, activity, count, link và direct URL.
- Không gửi email/AI/calendar/image provider thật trong local. Giữ adapter fake/preview mặc định; external provider chỉ qua server-side adapter với ENV + admin setting + consent từng lần.
- Không dùng Coding Plan/ZCode key hoặc endpoint Coding Plan cho runtime web app.
- Mọi lỗi bên dưới cần regression test thực sự chạy đúng endpoint/params, không test một 404 rồi coi là authorization pass.

============================================================
PHASE A — P0: CÔ LẬP CLIENT TRÊN DASHBOARD
============================================================

LỖI ĐÃ XÁC MINH

`DashboardController#index` chỉ scope `campaign_scope` cho client ở `app/controllers/dashboard_controller.rb:6-7`, nhưng các query sau vẫn là toàn organization:

- `@tasks_open_count` dòng 11
- `@pending_approvals_count` dòng 12
- `@my_tasks` dòng 15-16
- `@week_events` dòng 34-36
- `@recent_activity` dòng 39

Do đó client được mời vào 1 campaign có thể thấy metadata campaign khác qua `/`, dù direct campaign URL đã bị chặn.

CÁCH SỬA BẮT BUỘC

1. Tạo helper/query scope dùng chung, ví dụ `accessible_campaign_scope` hoặc `CampaignAccessScope`, trả về:
   - internal roles: tất cả campaign trong current organization;
   - `client` và `external_reviewer`: chỉ campaign có `campaign_collaborators.user_id = current_user.id`.
2. Mọi query Dashboard phải dùng `campaign_id IN accessible_campaign_scope.select(:id)`:
   - count task/open task;
   - count artifact in_review;
   - my tasks;
   - attention campaigns;
   - week events;
   - approvals;
   - notifications/link targets.
3. `AuditLog` không có campaign scope đáng tin cậy hiện tại. Với client/external reviewer, dùng `AuditLog.none` cho đến khi audit log có campaign_id/subject-to-campaign query an toàn. Không hiển thị activity toàn workspace.
4. Trong view, không render link/CTA nội bộ cho client/external reviewer (`Content Studio`, `Calendar`, `Clients`, `Templates`, `Settings`).

TEST BẮT BUỘC

- Tạo 2 campaign cùng org, client chỉ collaborator campaign A.
- `GET /` bằng session/client thật: response 200 nhưng body/count không chứa task title, event title, campaign name, approval metadata hay audit activity của campaign B.
- Direct URL campaign/artifact B vẫn redirect/403 và không leak title trong HTML.

============================================================
PHASE B — P0: SESSION/MEMBERSHIP PHẢI FAIL-CLOSED
============================================================

LỖI ĐÃ XÁC MINH

`Authentication#current_organization` ở `app/controllers/concerns/authentication.rb:15-20` tin `session[:org_id]` mà không xác minh user còn là member. Nếu membership bị xóa, `current_role` là nil nhưng `require_internal!` ở dòng 48 chỉ chặn role `client`, nên session cũ có thể vào CRM/studio/calendar/dashboard org cũ.

CÁCH SỬA BẮT BUỘC

1. Chỉ resolve org bằng quan hệ user:
   `current_user.organizations.find_by(id: session[:org_id])`.
2. Nếu `session[:org_id]` không hợp lệ/membership đã bị thu hồi:
   - xóa `session[:org_id]`;
   - chọn organization hợp lệ đầu tiên nếu còn; hoặc clear session + redirect login nếu không còn org;
   - tuyệt đối không trả về Organization chỉ từ global ID.
3. `require_internal!` phải fail closed:
   - return false/redirect nếu `current_role.blank?`;
   - chặn cả `client` và `external_reviewer`;
   - chỉ allow các role internal xác định rõ.
4. Rà soát `require_login`, `policy_for` và các before_action để một redirect/forbidden dừng action hoàn toàn.

TEST BẮT BUỘC

- Tạo session hợp lệ, sau đó xóa Membership của user cho org đó.
- Request `/`, `/clients`, `/content-studio`, `/calendar`, `/templates` không được trả dữ liệu và không có query/render record của org cũ.

============================================================
PHASE C — P0: APPROVAL VERSION INTEGRITY
============================================================

LỖI ĐÃ TÁI HIỆN

Flow lỗi:

1. Artifact version 1 được gửi round duyệt pending.
2. Editor PATCH artifact, tạo version 2 draft khi round v1 vẫn pending.
3. Reviewer approve round v1.
4. `ApprovalRound#sync_artifact_status` mark artifact version 2 là approved.

Nguyên nhân:

- `ArtifactsController#update` (`app/controllers/artifacts_controller.rb:15`) cho edit cả `in_review`.
- `Artifact#new_version!` (`app/models/artifact.rb:59-68`) không cancel/stale pending round cũ.
- `ApprovalRound#sync_artifact_status` (`app/models/approval_round.rb:50-60`) chỉ so ID round mới nhất, không so `artifact_version`, và dùng `update_column` bỏ validation/audit.

CÁCH SỬA BẮT BUỘC

Chọn một hành vi UX rõ ràng và implement nhất quán:

**Khuyến nghị:** khi editor sửa artifact đang `in_review`, tạo version mới nhưng atomically hủy mọi round pending của version cũ (`cancelled` + reason/audit) rồi đưa artifact về `draft`. Hoặc bắt user bấm `Withdraw` trước; không được để pending round cũ sống.

Ngoài ra bắt buộc:

1. Trong `Approvals::Decide`, dùng transaction + lock; từ chối quyết định nếu `round.artifact_version != round.artifact.version` hoặc artifact không còn `in_review` cho version đó.
2. Trong `ApprovalRound#sync_artifact_status`, chỉ sync khi:
   - round là latest non-cancelled round phù hợp; VÀ
   - `round.artifact_version == artifact.version`.
3. Không dùng `update_column` cho state business nếu có thể dùng transition/service audit hợp lệ. Nếu cần bypass do migration, giải thích và test rõ.
4. Giữ DB unique index reviewer/round và thêm protection against concurrent decision.

TEST BẮT BUỘC

- Regression test chính xác: submit v1 → edit thành v2 → reviewer quyết v1 → v2 phải còn draft, không được approved; v1 round cancelled/stale hoặc decision bị từ chối theo UX đã chọn.
- Test không thể submit/decide round đã cancelled/expired.
- Test quorum, reject và changes_requested không ghi đè round/version mới hơn.

============================================================
PHASE D — P0: CAMPAIGN-SCOPED REVIEWER / GUEST INVITE
============================================================

LỖI ĐÃ XÁC MINH

Dialog `Mời người duyệt` trong `app/views/campaigns/show.html.erb:522` submit vào `invite_members_path`, tạo workspace-wide `Invitation` với role `approver`.

Policy hiện chỉ giới hạn campaign đối với role `client` (`app/policies/policy.rb:33-42`). Vì vậy reviewer mới với role `approver` xem được toàn bộ campaign trong organization. Ngược lại role `client` không thể approve vì `ApprovalsController` yêu cầu quyền `:approve`.

Không có role nào vừa approve vừa bị giới hạn 1 campaign. Đây là blocker bảo mật/phạm vi.

CÁCH SỬA BẮT BUỘC

1. Tách hoàn toàn 2 loại invite:
   - **Workspace member invite** ở Members: internal role như manager/copywriter/approver, có phạm vi toàn org;
   - **Campaign reviewer/guest invite** ở Campaign Workspace: chỉ scope một campaign/artifact, không được chọn internal role.
2. Thêm role restricted, ví dụ `external_reviewer`, hoặc mô hình guest policy riêng. Role này:
   - chỉ có view/comment/approve theo `CampaignCollaborator.access` trên campaign được mời;
   - không vào CRM, member list, templates, content studio, settings, dashboard dữ liệu org-wide;
   - không có capability mặc định trên campaign khác.
3. Mở rộng `CampaignCollaborator::ACCESS` rõ ràng: `view`, `comment`, `approve`; policy map access → allowed permission. Không dựa vào role workspace chung để cấp approve cho guest.
4. Campaign invite modal phải post tới controller campaign-scoped, tạo `CampaignCollaboratorToken` gồm campaign, email, access, invited_by, signed/random token, expiry, revoke, accepted_at; preview/log mail local thôi.
5. Acceptance route nhận token phải chỉ tạo/cập nhật user + membership restricted cần thiết + CampaignCollaborator đúng campaign/access. Không cấp role `approver`/manager toàn workspace.
6. Chỉ allow owner/manager gửi/revoke campaign invite; ghi audit log scope campaign.

LỖI TÊN BẢNG PHẢI SỬA

Migration hiện tạo `campaign_collaborators_tokens`, trong khi model `CampaignCollaboratorToken` suy ra `campaign_collaborator_tokens`.

- Không sửa bằng drop table trong database người dùng.
- Tạo migration rename table an toàn (`rename_table`) và kiểm tra schema/index/foreign key;
- hoặc đặt `self.table_name` tạm thời kèm migration chuẩn hoá/backfill. Ưu tiên table name đúng Rails convention.
- Thêm test model/query để table mismatch không tái diễn.

TEST BẮT BUỘC

- External reviewer được mời campaign A: xem/approve artifact A được chỉ định, không xem campaign/artifact B.
- External reviewer bị 302/403 ở `/clients`, `/members`, `/templates`, `/content-studio`, `/calendar` và dashboard không leak dữ liệu B.
- Token expired/revoked/accepted lại bị từ chối.
- Workspace approver nội bộ giữ hành vi org-wide chỉ khi được mời qua Members, không qua campaign invite.

============================================================
PHASE E — P1: ROUTE/ACTION RUNTIME BUGS
============================================================

1. **Thu hồi collaborator hỏng**

`resources :collaborators, shallow: true` tạo `DELETE /collaborators/:id`, nhưng `CollaboratorsController#destroy` vẫn gọi `set_campaign` cần `params[:campaign_id]`.

Sửa theo một trong hai cách:

- bỏ `shallow: true` và dùng nested DELETE `/campaigns/:campaign_id/collaborators/:id`; hoặc
- trong destroy, tìm collaborator scoped an toàn qua `CampaignCollaborator.joins(:campaign).where(campaigns: { organization_id: current_organization.id }).find(params[:id])`, lấy `campaign = collaborator.campaign`, rồi authorize manage trên campaign.

Thêm request/system test click/revoke thành công và client mất quyền ngay sau đó.

2. **Image Studio POST hỏng**

`CampaignsController` only loads `@campaign` cho show/edit/update/generate; action `create_image_prompt` dùng `@campaign` nhưng không có `before_action` load nó.

Sửa `before_action :set_campaign` để bao gồm `:create_image_prompt`; thêm request test của authorized editor, assert image_prompt artifact được tạo. Test unauthorized/client không mutate.

3. **Task milestone/dependency chưa thật sự editable**

Migration/model có `milestone_id` và `depends_on_id`, nhưng task strong params/UI không cho cập nhật chúng. Hoặc implement đầy đủ scope-safe fields/form/routes; hoặc bỏ claim rằng user có thể quản lý dependency/milestone. Nếu implement:

- scope milestone/dependency trong đúng campaign;
- validation milestone cùng campaign;
- chặn self-dependency/cycle;
- test cross-campaign ID bị từ chối.

4. **Lifecycle/milestone/template chưa đủ như claim**

- `lifecycle_stage` hiện chỉ default, chưa có transition UI/controller/service.
- ProjectTemplate phải clone chính xác config được hứa (milestones/tasks/**artifact kinds**); nếu artifact kinds chưa clone thì implement hoặc không claim.
- PromptTemplate phải có CRUD/use thật trong content workflow, hoặc ghi rõ là data model chưa expose.

============================================================
PHASE F — P1: I18N/RUNTIME HEALTH
============================================================

LỖI ĐÃ XÁC MINH TRÊN SERVER THẬT

Đăng nhập `owner@demo.vn` rồi tải Dashboard đã trả 500:

`Translation missing: en.time.formats.datetime_short`

`UiHelper#fmt_datetime` gọi key này. `config/locales/en.yml` hiện chỉ có `hello`.

CÁCH SỬA BẮT BUỘC

1. Bổ sung ít nhất:

```yml
en:
  date:
    formats:
      short: "%m/%d/%Y"
  time:
    formats:
      datetime_short: "%H:%M · %m/%d/%Y"
```

2. Giữ `vi` là default; whitelist locale chỉ `vi/en`.
3. Dùng `I18n.with_locale`/around_action phù hợp để locale không bị leak giữa request; không set arbitrary `params[:locale]` không whitelist.
4. Thêm request/system tests:
   - login → `/` mặc định vi trả 200;
   - `/?locale=en` trả 200;
   - Dashboard, campaign show, artifact show với date/time không raise MissingTranslationData.
5. Sau đổi `config/application.rb`, phải stop/start Rails process (config không hot reload hoàn toàn). Không nói “đã test” nếu chỉ test runner với process mới nhưng server local cũ chưa restart.

============================================================
PHASE G — P1: NHẮC HẠN/EMAIL/CALENDAR/AI PHẢI ĐƯỢC MÔ TẢ VÀ THIẾT KẾ ĐÚNG
============================================================

Không được tuyên bố các phần dưới là production-complete khi hiện chỉ fake/offline:

1. Reminder
   - `Reminder.schedule!` hiện chủ yếu được gọi từ seed; task/event/approval chưa tự schedule reminder.
   - Thêm rule/service tạo/cancel reminder từ due date/meeting/approval theo workspace setting, hoặc ghi rõ feature chưa implemented.
   - `config/recurring.yml`/Solid Queue phải schedule dispatch thật trong môi trường worker; thêm test job scheduling/idempotency.

2. Email/calendar
   - Dev chỉ preview/log là đúng. Đừng tự gửi email.
   - Event attendee hiện phải là workspace user; nếu yêu cầu nghiệp vụ là mời email ngoài, implement separate consented invite/guest flow sau Phase D.
   - ICS export là feature MVP; Google/Outlook sync chỉ quảng cáo khi OAuth/provider adapter thật có credential và test.

3. AI/translation/image
   - Fake default phải giữ nguyên an toàn.
   - Workflow không được luôn inject fake completion khi external provider đã được cấu hình/gated hợp lệ. Chỉ dùng fake override khi provider là fake/local test.
   - Translation service phải chọn adapter qua provider config, không luôn instantiate Fake; image workflow phải ghi rõ hiện chỉ tạo **image prompt package**, không nói đã generate image nếu chưa có provider thật.
   - Không lưu raw client prompt/nội dung nhạy cảm không cần thiết trong `ai_metadata`; lưu reference/redacted data/hash + AiRun audit.
   - Thêm tests cho fake path và external-gate denial; không thực call network trong test.

============================================================
PHASE H — TEST/REPORT/ACCEPTANCE GATE
============================================================

1. Sửa test sai:
   - `spec/requests/authorization_p0_spec.rb` hiện POST `artifact_id` cho approvals trong khi controller cần `round_id`. Tạo ApprovalRound thật và test đúng action/service path.
2. Thêm regression specs cho MỌI bug Phase A–F, bao gồm:
   - client dashboard leakage;
   - revoked membership session;
   - stale approval version;
   - campaign-scoped reviewer invite/access;
   - token table/query;
   - collaborator DELETE;
   - image prompt POST;
   - vi/en dashboard rendering;
   - milestone/dependency cross-campaign validation nếu feature được expose.
3. Ưu tiên request/system test với session/auth thật khi có thể; không chỉ stub `current_user/current_role` cho security-critical flow.
4. Chạy và ghi output thật:

```powershell
$env:Path = "C:\Ruby33-x64\bin;" + $env:Path
cd E:\marketing-agentic-platform
bundle exec rails db:migrate
bundle exec rails db:seed
bundle exec rspec
```

5. Sau khi server cũ được dừng, chạy `.\start.ps1`, login owner ở `http://localhost:3000`, kiểm tra:
   - Dashboard không 500 ở vi/en;
   - campaign workspace desktop/mobile;
   - client/external reviewer scope;
   - approval v1/v2;
   - revoke collaborator;
   - image prompt;
   - reminder fake/in-app.
6. Cập nhật `docs/IMPLEMENTATION_REPORT.md` trung thực, phân biệt rõ:
   - **implemented + tested**;
   - **offline/mock MVP**;
   - **requires credential/business decision**.
7. Tạo `docs/REMEDIATION_REPORT.md` với: root cause, files/migrations changed, từng regression test, output test, manual smoke scenarios, screenshot paths và known limits.

ĐIỀU KIỆN KẾT THÚC

Không tuyên bố “đã hoàn tất” cho tới khi tất cả Phase A–F pass, 55 tests cũ và tests mới đều xanh, smoke test được thực hiện sau restart server, và không còn đường nào để client/external reviewer nhìn hoặc duyệt dữ liệu ngoài campaign được cấp.
```
