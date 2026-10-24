# Facebook Fanpage — kết nối, duyệt và đăng tự động

Module cho phép kết nối **Facebook Page của chính bạn** qua Meta OAuth, nhờ AI
viết bài, duyệt tay, lên lịch và để worker nền đăng lên Page bằng **Graph API
chính thức**. Mặc định **không bài nào lên Facebook nếu chưa có người duyệt**.

```
Dán link Fanpage → Đăng nhập Facebook (OAuth) → chọn Page → token mã hoá lưu server
AI nháp bài → xem trước/sửa → Gửi duyệt → Duyệt/Từ chối → Lên lịch (ngày, giờ, múi giờ)
→ FacebookPublishJob (Solid Queue) → POST /{page-id}/feed hoặc /photos → lưu post ID + permalink
```

## 1. Kiến trúc (file chính)

| Lớp | File |
|---|---|
| Cấu hình ENV, phiên bản API, scope | `app/services/facebook/config.rb` |
| Mã hoá token (AES-256-GCM) | `app/services/facebook/token_cipher.rb` |
| OAuth state ký + nonce session (chống CSRF) | `app/services/facebook/oauth_state.rb` |
| Graph API client thật / mock | `app/services/facebook/graph_api/http_client.rb`, `mock_client.rb` |
| Đổi code → token dài hạn, lấy danh sách Page, debug_token | `app/services/facebook/oauth.rb`, `begin_authorization.rb`, `connect_page.rb` |
| Chẩn đoán quyền/token | `app/services/facebook/diagnostics.rb` |
| State machine bài đăng | `app/models/facebook_post.rb`, `app/services/facebook/posts/transitions.rb` |
| Kiểm tra trước khi đăng, đăng, retry, đối soát | `app/services/facebook/posts/validate.rb`, `publish.rb`, `backoff.rb`, `reconcile.rb` |
| Job nền | `app/jobs/facebook_publish_job.rb`, `facebook_dispatch_due_job.rb`, `facebook_post_draft_job.rb` |
| AI viết bài | `app/services/ai/workflows/facebook_post_draft.rb` |
| UI | `app/controllers/facebook/*`, `app/views/facebook/*` |

Trạng thái bài: `draft → pending_approval → approved → scheduled → publishing →
published | failed | cancelled`. Không có đường tắt nào từ draft/pending sang
publishing (`FacebookPost::TRANSITIONS`, có test).

## 2. Tạo Meta Developer App (làm một lần)

1. Vào <https://developers.facebook.com/apps> → **Create App** → chọn loại
   **Business** (hoặc "Other → Business").
2. Trong app: **Add product → Facebook Login for Business** (hoặc Facebook Login).
3. **Facebook Login → Settings**:
   - *Client OAuth login*: ON. *Web OAuth login*: ON. *Enforce HTTPS*: ON (production).
   - **Valid OAuth Redirect URIs**: thêm **chính xác**
     `https://<APP_HOST>/facebook/connection/callback`
     (dev: `http://localhost:3000/facebook/connection/callback`).
     Trang `/facebook/connection` trong app hiển thị URI cần khai để copy.
4. **App settings → Basic**: lấy **App ID** và **App Secret**. Điền *App domains*
   (`<APP_HOST>`), *Privacy Policy URL* (bắt buộc khi chuyển Live).
5. **App Roles → Roles**: thêm tài khoản Facebook của bạn làm **Administrator/
   Developer/Tester** của app. Khi app còn ở chế độ *Development*, **chỉ các tài
   khoản này** đăng nhập được và chỉ đăng được lên Page mà họ quản lý — đủ để
   dùng cho Fanpage của chính bạn.
6. **Use cases / Permissions**: bật 3 quyền:
   `pages_show_list`, `pages_read_engagement`, `pages_manage_posts`.
   (`pages_read_engagement` là quyền Meta yêu cầu đi kèm `pages_manage_posts`.)
7. Tài khoản Facebook dùng để kết nối phải có vai trò **Quản trị viên** hoặc
   **Biên tập viên** trên Page (task `CREATE_CONTENT`). Kiểm tra tại
   *Page → Cài đặt → Quyền truy cập Page*.

### Khi nào cần App Review?
- **Không cần** nếu chỉ bạn (và người có role trong app) đăng lên Page của mình
  — app ở chế độ Development vẫn gọi được Graph API với Page mình quản lý.
- **Cần App Review + Business Verification** nếu muốn người dùng Facebook bất kỳ
  (ngoài app roles) kết nối Page của họ, hoặc chuyển app sang Live. Nộp review
  cho đúng 3 quyền trên kèm video màn hình quy trình kết nối → duyệt → đăng.

## 3. Biến môi trường

```bash
FACEBOOK_APP_ID=                 # App ID
FACEBOOK_APP_SECRET=             # App Secret — KHÔNG commit
FACEBOOK_GRAPH_API_VERSION=v23.0 # mặc định v23.0; Meta hỗ trợ mỗi version ~2 năm
FACEBOOK_REDIRECT_URI=           # tuỳ chọn; mặc định https://<APP_HOST>/facebook/connection/callback
FACEBOOK_TOKEN_ENCRYPTION_KEY=   # khoá mã hoá token Page (openssl rand -hex 32). Khuyến nghị production.
                                 # Để trống → dẫn xuất từ SECRET_KEY_BASE (đổi SECRET_KEY_BASE sẽ phải kết nối lại Page).
FACEBOOK_PUBLISHING_ENABLED=true # kill switch cấp triển khai; =false → mọi bài giữ nguyên scheduled, không gọi API
FACEBOOK_PUBLISH_MAX_ATTEMPTS=5  # số lần thử tối đa cho lỗi tạm thời
FACEBOOK_MOCK_MODE=false         # =true CHỈ ở dev/test: mô phỏng OAuth + đăng (bị bỏ qua trên production)
```

`.env.example` đã có đủ các khoá trên.

## 4. Xử lý token

- Luồng: `code` → user token ngắn hạn → `fb_exchange_token` → **user token dài
  hạn (~60 ngày)** → `/me/accounts` trả **Page token** cho từng Page. Page token
  lấy từ user token dài hạn **không hết hạn** (trừ khi đổi mật khẩu/thu hồi quyền).
- Chỉ **Page token** được lưu (`facebook_page_connections.access_token_ciphertext`),
  mã hoá AES-256-GCM. User token chỉ sống trong bảng tạm
  `facebook_authorizations` (mã hoá, hết hạn 15 phút, xoá ngay khi chọn Page).
- Token không bao giờ: render ra view, vào JSON, vào log (`filter_parameters`
  lọc `access_token/code/state`; `inspect` model hiển thị `[FILTERED]`).
  Mọi request gắn `appsecret_proof`.
- Hết hạn/thu hồi (lỗi 190) → kết nối chuyển `token_expired`, bài đang chờ
  thành `failed` với hướng dẫn "Kết nối lại".

## 5. Chạy thử không cần Meta (mock)

```bash
cp .env.example .env
# trong .env: FACEBOOK_MOCK_MODE=true
bundle exec rails db:prepare && bundle exec rails db:seed
bundle exec rails server        # http://localhost:3000  (owner@demo.vn / password123)
```

Vào **Facebook Fanpage** → dán link bất kỳ (vd `https://www.facebook.com/marketflow.demo`)
→ "Đăng nhập Facebook & kết nối" → Page giả được kết nối, gắn nhãn **MOCK**.
Tạo bài AI → gửi duyệt → duyệt → "Đăng ngay": bài được đánh dấu `published`
với `published_via = mock` và ID có tiền tố `mock`. **Không gì lên Facebook.**

Dev dùng Active Job adapter `:async`: bài lên lịch chỉ đăng khi tiến trình
server còn chạy. Production dùng Solid Queue (bền, xem mục 7).

Ghi chú khi chạy local:
- `.env` được nạp tự động ở **development** (gem `dotenv`, nhóm development).
  Test không đọc `.env`; production nhận ENV từ docker/kamal. Sửa `.env` xong
  phải **khởi động lại server**.
- Giữ dòng `SECRET_KEY_BASE` ở dạng comment trong `.env` dev. Dòng
  `SECRET_KEY_BASE=` rỗng làm Rails dev lỗi khởi động.
- Windows: gọi `C:\Ruby33-x64\bin\bundle.bat` (hoặc `.\start.ps1`) để tránh
  shim `bundle` của Node.js.
- Các nút Duyệt / Đăng ngay / Huỷ có hộp xác nhận của trình duyệt — bấm OK.

Đã kiểm thử thủ công trên máy local (mock): kết nối Page → AI nháp → gửi duyệt
→ duyệt → Đăng ngay; và bài tự viết → duyệt → lên lịch +2 phút → job tự đăng
đúng giờ.

## 6. Kết nối Fanpage thật (an toàn)

1. Điền `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET`, `FACEBOOK_TOKEN_ENCRYPTION_KEY`
   vào `.env` / `.env.production`. Tắt `FACEBOOK_MOCK_MODE`.
2. Đảm bảo Redirect URI khớp **chính xác** (scheme + host + path).
3. Đăng nhập app bằng tài khoản owner/admin/manager → **Facebook Fanpage** →
   dán link Fanpage → đăng nhập Facebook bằng tài khoản **quản trị Page** và
   **chấp nhận cả 3 quyền**. Nếu bỏ sót quyền, trang kết nối sẽ báo "Thiếu
   quyền" kèm nút Kết nối lại.
4. Bấm **Chẩn đoán kết nối**: phải thấy "token hợp lệ, đủ quyền".
5. Thử nghiệm thật: tạo một bài text ngắn → gửi duyệt → duyệt → **Đăng ngay**.
   Trang bài hiện ID bài + link "Xem trên Facebook". Nếu thất bại, mục *Lịch sử
   đăng* ghi mã lỗi Meta + `fbtrace_id` để tra cứu.
6. Sau khi text ổn định mới dùng bài ảnh (JPG/PNG/GIF/WEBP ≤ 4 MB). Video
   **chưa hỗ trợ** (cần Resumable Upload API, triển khai sau).

Mặc định an toàn: mọi bài phải được duyệt. Chỉ bật **Tự động đăng** cho Page +
campaign cụ thể trong mục *An toàn & phê duyệt* khi thật sự muốn.

## 7. Triển khai production

- Worker **bắt buộc**: `bin/jobs` (Solid Queue) — `docker-compose.prod.yml`
  đã có service `worker`. Không có worker thì bài nằm ở `scheduled` mãi.
- `config/recurring.yml`: `FacebookDispatchDueJob` chạy mỗi 2 phút — lưới an
  toàn đẩy bài tới giờ nếu job delay mất sau restart và đối soát bài kẹt ở
  `publishing` (đọc feed Page: thấy bài trùng → `published`, không thấy →
  `failed/publish_state_unknown`, cần người kiểm tra trước khi thử lại — tránh
  đăng trùng).
- HTTPS bắt buộc cho redirect URI; `APP_HOST` phải đúng tên miền.
- Kill switch: ENV `FACEBOOK_PUBLISHING_ENABLED=false` (toàn hệ thống) hoặc nút
  **Tạm dừng toàn bộ** (owner/admin, theo workspace), hoặc tạm dừng từng Page.
- Phiên bản Graph API ghim qua `FACEBOOK_GRAPH_API_VERSION`; theo dõi
  [lịch ngừng hỗ trợ](https://developers.facebook.com/docs/graph-api/changelog)
  và nâng version mỗi ~1 năm.
- Rate limit: hệ thống tự backoff 1→2→4→8→16 phút (+jitter, trần 30 phút),
  tối đa 5 lần; lỗi quyền/token/validation/policy không retry.

## 8. Kiểm thử

```bash
bundle exec rspec spec/services/facebook spec/requests/facebook
```

Toàn bộ test dùng **MockClient hoặc client stub** — không gọi Meta. Chúng
kiểm tra: state OAuth (chữ ký, nonce, hết hạn, đổi user), phân quyền, cổng
duyệt (draft/pending không thể đăng), múi giờ, backoff/retry có giới hạn,
idempotency (token lịch, khoá publishing, không đăng lại sau published), phân
loại lỗi Meta, mã hoá token, đối soát bài kẹt.

**Chưa có kiểm thử đăng thật** lên một Page Facebook thật trong repo này —
việc đó cần App ID/Secret và tài khoản quản trị Page của bạn (mục 6).

## 9. Những gì bạn phải cấu hình thủ công

1. Tạo Meta App, bật Facebook Login, khai Redirect URI, lấy App ID/Secret (mục 2).
2. Thêm tài khoản Facebook của bạn vào App Roles (hoặc nộp App Review nếu mở
   cho người ngoài).
3. Điền ENV (mục 3) và khởi động lại `app` + `worker`.
4. Tài khoản kết nối phải là quản trị viên/biên tập viên của Page.

## 10. Hội nhóm Facebook — chia sẻ bằng tay, có nhắc giờ

Meta đã gỡ **Groups API** (Graph API v19.0, đầu năm 2024; quyền
`publish_to_groups` bị thu hồi ở mọi version). Không phần mềm nào đăng vào nhóm
được bằng cách chính thức. Công cụ "auto đăng nhóm" bằng điều khiển trình duyệt
vi phạm điều khoản Meta và dễ làm khoá tài khoản/Page, nên MarketingOS **không**
làm việc đó. Thay vào đó, app chuẩn bị mọi thứ để người dùng tự đăng thật nhanh:

```
Danh sách nhóm (nhập tay: link, nhãn, luật nhóm, cho/cấm link, người phụ trách)
→ Bài đã lên Page → "Chia sẻ vào hội nhóm": chọn nhóm, giờ bắt đầu, giãn cách
→ mỗi nhóm một lượt chia sẻ, giờ hẹn cách nhau (mặc định 30 phút)
→ đến giờ: Reminder (in-app/email theo cài đặt từng người)
→ trang "Việc chia sẻ hội nhóm": Sao chép nội dung · Sao chép link bài Page
  · Tải ảnh · Mở nhóm → người dùng tự đăng → dán link bài trong nhóm
→ Đã đăng | Admin từ chối | Bỏ qua (mở lại được)
```

| Lớp | File |
|---|---|
| Model | `app/models/facebook_group.rb`, `app/models/facebook_group_share.rb` |
| Lên kế hoạch, giãn cách, chọn người phụ trách | `app/services/facebook/group_shares/plan.rb` |
| Đánh dấu kết quả, đổi giờ, mở lại, xoá | `app/services/facebook/group_shares/transitions.rb` |
| Nhắc giờ (dùng lại `Reminder`) | `app/services/facebook/group_shares/reminders.rb` |
| AI viết mỗi nhóm một bản | `app/services/ai/workflows/facebook_group_variants.rb`, `app/jobs/facebook_group_variants_job.rb` |
| UI | `app/controllers/facebook/groups_controller.rb`, `group_shares_controller.rb`, `app/views/facebook/group_shares/*`, `app/views/facebook/groups/*` |

Chi tiết:
- **Link nhóm** được chuẩn hoá về `https://www.facebook.com/groups/<id>` (bỏ
  `?ref=...`, `m.`/`web.`). Một nhóm chỉ có một lần trong mỗi workspace.
- **Giãn cách** 10–120 phút. Đăng dồn cùng lúc vào nhiều nhóm dễ bị Facebook coi
  là spam. Nhóm đã có trong kế hoạch của bài thì không tạo trùng.
- **Người phụ trách**: chọn khi lên kế hoạch; để trống thì theo người phụ trách
  mặc định của nhóm, không có nữa thì là người lên kế hoạch. Chỉ thành viên nội
  bộ (không giao cho client).
- **Nhắc giờ**: mỗi lượt có một `Reminder` (khoá `fb_group_share:<id>:...`) theo
  kênh người phụ trách chọn ở Cài đặt, và một `ReminderDispatchJob` đặt **đúng
  giờ hẹn** (sweeper production chỉ chạy 30 phút/lần). Đổi giờ/người → lời nhắc
  cũ bị huỷ; đánh dấu xong/xoá → huỷ lời nhắc.
- **AI biến thể** (tuỳ chọn): giữ nguyên dữ kiện (giá, diện tích, SĐT), chỉ đổi
  câu mở đầu và cách viết; nhóm cấm link thì không chèn URL. Sửa tay nội dung sẽ
  bỏ nhãn "AI viết lại". Provider thật chạy nền và báo qua thông báo.
- **Xoá nhóm** đã có lịch sử chia sẻ chỉ ẩn nhóm (giữ báo cáo); quyền xoá = manage.
- Mọi thao tác ghi `AuditLog` (`facebook.group.*`, `facebook.group_share.*`).

Kiểm thử: `spec/models/facebook_group_spec.rb`,
`spec/services/facebook/group_shares_spec.rb`,
`spec/requests/facebook/group_shares_spec.rb` (gửi form bằng đúng tên trường đọc
từ HTML đã render, quyền, cách ly workspace, nhắc giờ, email).
