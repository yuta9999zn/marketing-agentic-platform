# MarketingOS — Marketing Operations & Collaboration Platform (MVP)

Workspace cho đội marketing nội bộ, agency và khách hàng cùng làm việc trên campaign:
**Client → Brief → Research/Persona → Content plan → Góp ý & version → Approval →
Task/Timeline → Meeting (ICS) → Deliverable**, với AI luôn ở vai trò trợ lý nháp
và con người ra quyết định cuối.

## Yêu cầu

- Ruby 3.3 (`C:\Ruby33-x64`) — trên Windows dùng PowerShell:
  `$env:Path = "C:\Ruby33-x64\bin;" + $env:Path` (tránh Node `bundle` shim).
- Git, Node (asset pipeline). Docker + Postgres chỉ cần cho production-like.
- Harness `cdfl_harness` được vendor sẵn trong `vendor/gems/cdfl_harness` — không
  cần bản gốc ở `D:\CDFL harness` để chạy. Sửa harness gốc rồi đồng bộ lại bằng
  `bin/sync_harness`.

## Khởi động nhanh

Cách dễ nhất — chạy script khởi động (tự set PATH đúng, migrate, seed nếu cần, start server):

```powershell
cd E:\marketing-agentic-platform
.\start.ps1
```

Hoặc gõ thủ công. **Quan trọng trên máy này**: PATH có shim `bundle` của Node.js
(package `script` trong nvm) nằm trước Ruby, nên phải đưa Ruby lên trước trong
từng session PowerShell, nếu không sẽ dính lỗi
`TypeError [ERR_INVALID_ARG_TYPE] ... at bundle:38`:

```powershell
$env:Path = "C:\Ruby33-x64\bin;" + $env:Path
bundle install
bundle exec rails db:migrate
bundle exec rails db:seed      # dữ liệu demo
bundle exec rails server       # http://localhost:3000
```

Gọi thẳng khi không muốn sửa PATH: `C:\Ruby33-x64\bin\bundle.bat exec rails server`.
Lưu ý Windows PowerShell 5.1 không hỗ trợ `&&` — chạy từng lệnh riêng, hoặc dùng `.\start.ps1`.

Muốn hết vĩnh viễn (tùy chọn): `npm uninstall -g script` hoặc chỉnh system PATH
đưa `C:\Ruby33-x64\bin` lên trước thư mục nvm.

Tài khoản demo (dữ liệu giả): `owner@demo.vn` / `password123`
(cùng mật khẩu cho manager/strategist/copy/design/approver/client `@demo.vn`).

## Chạy test

```powershell
$env:RAILS_ENV = "test"; bundle exec rails db:migrate
bundle exec rspec
```

Mọi test AI dùng Fake adapter của harness — **không gọi mạng**.

## An toàn & AI runtime

- Mọi lời gọi model đi qua `Ai::Gateway` bọc `CDFLHarness::Gateway::Client`
  (single chokepoint). Mặc định `AI_PROVIDER=fake`: offline, deterministic.
- Provider ngoài cần **double consent**: `AI_EXTERNAL_ENABLED=true` (master
  switch, xem `.env.example`) **và** tick xác nhận từng lần gọi trong UI.
  Không đủ điều kiện → harness tự downgrade về local.
- Audit: mỗi lời gọi AI ghi vào bảng `ai_calls` — chỉ SHA-256 hash prompt/output,
  không lưu văn bản thô. Hành động nghiệp vụ ghi `audit_logs`.
- Artifact AI luôn là **draft**, gắn nhãn `AI-generated`/`AI-assisted`, lưu
  prompt + provider + thời gian + trạng thái rà soát bởi con người; phải qua
  approval mới thành chính thức. AI khai báo "thiếu dữ liệu" thay vì bịa.
- Email chỉ là giao dịch (lời mời, duyệt). Dev: adapter test/log, không gửi thật.
- Không có scraping, bulk mail. Đăng Facebook chỉ qua Graph API chính thức, sau khi
  có người duyệt (xem mục Facebook Fanpage).

## Multi-tenant & quyền

- Mọi bản ghi nghiệp vụ gắn `organization_id`; truy vấn controller luôn scope
  theo organization hiện tại; policy RBAC chạy phía server (`app/policies/policy.rb`):
  `view < comment < edit < approve < manage < admin`.
- Vai trò: owner, admin, manager, strategist, copywriter, designer,
  project_manager, approver, client (client chỉ thấy campaign được mời qua
  collaborator).
- Lời mời: signed token, hết hạn 7 ngày, thu hồi được, ghi audit.

## Cấu trúc chính

```
app/
  controllers/    # auth, campaigns, artifacts, approvals, tasks, comments, events,
                  # members, clients (CRM), calendar, templates, prompt_templates,
                  # user_settings, facebook/ (connection OAuth + posts)
  services/facebook/     # OAuth, token cipher, Graph API client (live/mock), publish/retry
  jobs/           # AI nền, nhắc nhở, FacebookPublishJob / FacebookDispatchDueJob
  models/         # organization, membership, campaign, artifact (+versions), approval,
                  # prompt_template, project_template, reminder...
  policies/       # RBAC trung tâm
  services/ai/    # gateway.rb (chokepoint) + workflows (brief, persona, content plan, script)
  services/campaigns/    # create_from_template, save_as_template
  services/reminders/    # schedule_for_task, schedule_for_event, resync, dispatch_due
  services/notifications/
config/locales/   # vi.yml, en.yml — toàn bộ copy giao diện
db/seeds.rb       # dữ liệu demo + 8 prompt mẫu marketing + chạy AI fake offline
docs/PHASE1_REPORT.md
docker-compose.yml  # Postgres + Mailpit (tùy chọn)
```

## AI chạy trên máy (Ollama)

Mặc định app chạy provider `fake` (offline, tức thì). Bật AI thật:

```powershell
# 1. Tải model (một lần) — qwen2.5:7b viết tiếng Việt tốt và bám JSON schema
D:\Ollama\ollama.exe pull qwen2.5:7b

# 2. Chạy Ollama server
$env:OLLAMA_MODELS = "D:\Ollama\models"
D:\Ollama\ollama.exe serve

# 3. Chạy app với provider ollama
$env:AI_PROVIDER = "ollama"; $env:OLLAMA_MODEL = "qwen2.5:7b"
.\start.ps1
```

- **Dữ liệu không rời khỏi máy.** Harness coi Ollama là `internal` nên không cần
  `AI_EXTERNAL_ENABLED` và không phải tick consent — hai thứ đó chỉ dành cho
  provider bên thứ ba.
- **Tác vụ AI chạy nền**: sinh nội dung mất 20-90 giây nên request trả về ngay,
  người dùng nhận thông báo trong ứng dụng khi bản nháp sẵn sàng.
- Giao diện hiện trạng thái thật (*"Chạy trên máy · qwen2.5:7b"*, hoặc đỏ nếu
  không kết nối được). Không kết nối được thì báo lỗi, **không** âm thầm trả kết
  quả giả.
- Đừng dùng model quá nhỏ (`llama3.2:1b`): đã đo, nó không trả nổi JSON hợp lệ.
- **Ollama không tạo được ảnh** — nó viết prompt ảnh chất lượng cao, còn render
  ảnh cần dịch vụ riêng.

## Facebook Fanpage — duyệt rồi đăng tự động

Kết nối Page qua Meta OAuth (dán link Fanpage → đăng nhập Facebook → chọn Page),
AI viết caption/hashtag/CTA, **bắt buộc duyệt tay** rồi lên lịch; worker nền đăng
qua Graph API chính thức, lưu post ID + permalink, retry có giới hạn, kill switch,
audit log. Token Page mã hoá at rest, không ra frontend/log.

- Thử ngay không cần Meta: `FACEBOOK_MOCK_MODE=true` (chỉ dev/test; bài gắn nhãn MOCK).
- Kết nối Page thật: điền `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET`,
  `FACEBOOK_TOKEN_ENCRYPTION_KEY`; khai Redirect URI trong Meta App.
- Hướng dẫn đầy đủ (tạo app, quyền, token, ENV, triển khai, App Review):
  `docs/FACEBOOK_PUBLISHING.md`.
- Production: worker `bin/jobs` bắt buộc; `FacebookDispatchDueJob` chạy mỗi 2 phút
  (`config/recurring.yml`).

## Đa ngôn ngữ

- Giao diện có tiếng Việt và tiếng Anh; toàn bộ copy nằm trong
  `config/locales/vi.yml` / `en.yml`, không viết cứng trong view.
- Người dùng chọn ngôn ngữ ở nút VI/EN trên thanh trên cùng hoặc trong
  `/settings` — tùy chọn lưu theo tài khoản. `?locale=en` ghi đè cho một request.

## Nhắc nhở

- Mỗi người tự đặt "nhắc trước bao lâu" (15 phút → 2 ngày) và kênh nhắc
  (trong ứng dụng, hoặc kèm email) tại `/settings`.
- Áp dụng cho việc đến hạn và sự kiện mình tham dự. Đổi cài đặt thì lịch nhắc
  được dựng lại, mốc cũ bị hủy — không nhắc trùng.
- Gửi định kỳ thật cần chạy worker: `bin/jobs` (Solid Queue), hoặc cron gọi
  `ReminderDispatchJob`. Email hiện dùng adapter test — **chưa gửi thật**.

## Triển khai lên VPS

**Đang chạy thật:** https://187-77-127-200.sslip.io (VPS Hostinger `187.77.127.200`).
Xem `docs/DEPLOY_VPS.md` và `docs/DEPLOY_REPORT.md`.

```bash
cp .env.example .env.production   # điền SECRET_KEY_BASE, APP_HOST, SMTP…
docker compose -f docker-compose.prod.yml --env-file .env.production --profile ai up -d --build
docker compose -f docker-compose.prod.yml exec ollama ollama pull qwen2.5:7b
```

Ba dịch vụ: `app` (web), `worker` (Solid Queue — **bắt buộc**, thiếu nó thì tác vụ
AI nằm mãi trong hàng đợi), `ollama` (AI nội bộ, tuỳ chọn).

Cấu hình VPS tối thiểu: **1 vCPU / 1 GB** nếu không chạy AI; **4 vCPU / 8 GB** nếu
chạy `qwen2.5:7b` trên chính VPS. Chi tiết và cách đo tốc độ thật: `docs/DEPLOY_VPS.md`.

Gem harness được vendor trong `vendor/gems/cdfl_harness` để build được trên Linux.
Khi harness gốc cập nhật: `bin/sync_harness` rồi `bundle install`.

## Tài liệu thêm

- `docs/FACEBOOK_PUBLISHING.md` — Facebook Fanpage: Meta app, OAuth, quyền, token, ENV, triển khai.
- `docs/DEPLOY_VPS.md` — hướng dẫn triển khai VPS; `docs/DEPLOY_REPORT.md` — các
  lỗi chặn triển khai đã tìm ra và kết quả chạy thật (mới nhất).
- `docs/PHASE3_REPORT.md` — AI thật chạy trên máy: Ollama, tác vụ chạy nền, dịch
  bằng mô hình ngôn ngữ, dịch nhanh tại chỗ, khảo sát + phân tích (mới nhất).
- `docs/PHASE1_REPORT.md` — đa ngôn ngữ, cài đặt cá nhân & nhắc nhở,
  thư viện template, CRM khách hàng, lịch nội dung.
- `docs/IMPLEMENTATION_PLAN.md` — kiến trúc, milestone.
- `docs/IMPLEMENTATION_REPORT.md`, `docs/REMEDIATION_REPORT.md` — các phase trước.
- Harness: `D:\CDFL harness\docs\` (GATEWAY, AGENT_LOOP, INVARIANTS...).
