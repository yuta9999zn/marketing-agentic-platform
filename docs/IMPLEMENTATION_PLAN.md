# MarketingOS — Implementation Plan

Marketing Operations & Collaboration Platform có AI hỗ trợ (MVP, chạy local Windows).

## Kiến trúc

- **Monolith Rails 8** (Ruby 3.3), SQLite cho development/test, docker-compose Postgres cho production-like.
- **UI**: Hotwire (Turbo + Stimulus), Tailwind qua CDN trong MVP, không thêm frontend framework thứ hai.
- **AI**: mọi lời gọi model đi qua `Ai::Gateway` — wrapper mỏng bọc `CDFLHarness::Gateway::Client`
  (gem `cdfl_harness` vendored trong `vendor/gems/cdfl_harness`). Mặc định provider `:fake`
  (không mạng). Provider ngoài chỉ bật khi `AI_EXTERNAL_ENABLED=true` **và** người dùng tick
  consent từng lần gọi (double-gate K-4 của harness). PII middleware + audit sink của harness
  được bật: audit ghi vào bảng `ai_calls` (chỉ hash prompt/output).
- **Background jobs**: Solid Queue; job idempotent.
- **Realtime**: Turbo Streams cho comment/approval/notification.
- **Email**: log/mailpit dev; SMTP/Resend qua ENV cho production. Chỉ email giao dịch.
- **Calendar MVP**: bảng `events` + export ICS; Google/Outlook OAuth chỉ là interface placeholder (P1).

## Multi-tenant & RBAC

- `organizations` — mọi bản ghi nghiệp vụ đều có `organization_id`, default_scope lọc theo
  current organization của session; policy kiểm tra ở controller/service, không chỉ ẩn UI.
- `memberships.role`: owner/admin, manager, strategist, copywriter, designer, project_manager,
  approver, client.
- Quyền hiệu lực: view < comment < edit < approve < manage < admin. Client/guest chỉ thấy
  campaign được mời (bảng `campaign_collaborators`).
- Invite qua signed token có expiry, revoke được, ghi audit log.

## Luồng nghiệp vụ

Client/Brand → Campaign → Brief (AI draft) → Persona (AI draft) → Content plan → Version &
góp ý → Approval → Task/Timeline → Event/ICS → Deliverable → Review & tái dùng template.

AI output luôn là **draft**: gắn nhãn `AI-generated`, lưu metadata (provider, model, prompt,
thời gian), phải được con người duyệt trước khi thành artifact chính thức (decline-not-hallucinate
tương thích coverage gate của harness).

## Milestones

1. ✅ Scaffold Rails 8 + gem cdfl_harness + RSpec.
2. Schema + models: Organization, User/Membership, Invitation, Client, Campaign,
   Artifact/ArtifactVersion, Approval, Task, Comment, Event, Notification, AuditLog, AiCall.
3. Auth (session, bcrypt) + current organization + policies RBAC.
4. Ai::Gateway (Fake mặc định, consent double-gate, audit sink) + workflows:
   brief draft, persona draft, content draft.
5. UI cơ bản: dashboard, campaign show (tabs: brief, personas, content, tasks, approvals,
   comments), wizard tạo campaign.
6. Approval flow + notifications + Turbo Streams.
7. Events + ICS export.
8. Seeds demo + specs (models, policies, request, AI dùng Fake adapter — không mạng).
9. `.env.example`, docker-compose Postgres, README.

## Giả định & hoãn (deferred)

- Chưa có billing/subscription (chỉ mock trang settings).
- Google/Outlook calendar OAuth: P1, chỉ interface + tài liệu.
- Prompt template library & tái dùng: P1 (khung `artifacts.template` đã có trường).
- Production mailer: cấu hình ENV, không gửi mail thật trong MVP.
- Image generation: P1 — chỉ giữ prompt-ảnh field cho Designer, không gửi ảnh ra provider ngoài.
