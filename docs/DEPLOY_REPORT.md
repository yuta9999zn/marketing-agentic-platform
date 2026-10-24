# Sẵn sàng triển khai VPS — báo cáo kiểm chứng

Ngày: 2026-08-17. Trạng thái: **203/203 RSpec pass** (193 cũ + 10 spec triển khai).
Stack production đã **build và chạy thật** trên Docker Linux container, không phải
kiểm tra bằng đọc file.

---

## Lỗi chặn triển khai đã tìm ra và sửa

Bốn lỗi này khiến app **không thể** chạy trên VPS. Ba trong số đó chỉ lộ ra khi
build/chạy thật, không lộ khi chạy dev trên Windows.

### 1. Gemfile trỏ vào đường dẫn Windows tuyệt đối (chặn hoàn toàn)

```ruby
gem "cdfl_harness", path: "D:/CDFL harness"   # trước
gem "cdfl_harness", path: "vendor/gems/cdfl_harness"   # sau
```

Linux không có ổ `D:`. Docker build hỏng ngay bước `bundle install`.

**Sửa:** vendor gem vào `vendor/gems/cdfl_harness` (241 KB, 68 file — chỉ `lib`,
`docs`, gemspec, README, LICENSE; không lấy `.git` và `spec`). Thêm `bin/sync_harness`
để đồng bộ lại khi harness gốc cập nhật.

### 2. Dockerfile làm mất một cấp thư mục khi copy vendor

```dockerfile
COPY vendor/* ./vendor/    # SAI: đổ nội dung thư mục con lên thẳng vendor/
COPY vendor/ ./vendor/     # ĐÚNG: giữ nguyên vendor/gems/cdfl_harness
```

Docker `COPY dir/* dest/` khai triển glob rồi copy **nội dung** của từng thư mục con,
nên `vendor/gems/cdfl_harness` sẽ thành `vendor/cdfl_harness` — đúng cái đường dẫn
mà Gemfile không tìm thấy.

### 3. Seeds gọi model thật → container không khởi động được lần đầu

Đây là lỗi nghiêm trọng nhất và chỉ phát hiện khi chạy thật:

```
app-1 | bin/rails aborted!
app-1 | CDFLHarness::Errors::AdapterError: ollama /api/generate → 404:
app-1 |   {"error":"model 'qwen2.5:3b' not found"}
app-1 | Tasks: TOP => db:prepare
```

Chuỗi sự kiện: entrypoint chạy `db:prepare` → database mới nên Rails chạy `db:seed`
→ `db/seeds.rb` gọi `Ai::Workflows::CampaignBrief.call` → provider là `ollama` nhưng
model **chưa tải** (mới dựng máy, chưa ai `ollama pull`) → seeds ném lỗi →
`db:prepare` thất bại → `bash -e` trong entrypoint dừng → container chết.

App tự phục hồi ở lần restart thứ hai (database đã tồn tại nên Rails bỏ qua seeds),
nhưng `worker` thì **không bao giờ lên** vì `depends_on: service_healthy` đã hết
thời gian chờ. Kết quả: web chạy nhưng mọi tác vụ AI nằm mãi trong hàng đợi.

**Sửa:** seeds chỉ tạo nội dung AI khi provider là `fake` (tức thì, offline). Provider
thật thì in thông báo và bỏ qua; lỗi bất ngờ cũng chỉ cảnh báo, không dừng. Dữ liệu
demo không được phép chặn triển khai.

### 4. Worker khởi động trước khi database được migrate

`app` là nơi chạy `db:prepare`, nhưng `worker` không có ràng buộc thứ tự — nó khởi
động song song và Solid Queue không tìm thấy bảng hàng đợi.

**Sửa:** `worker` phụ thuộc `app` với điều kiện `service_healthy`.

---

## Cấu hình production đã chuyển sang biến môi trường

Trước đây `production.rb` ghi cứng `example.com` và để SMTP dạng comment.

| Biến | Tác dụng | Bỏ trống thì |
|---|---|---|
| `SECRET_KEY_BASE` | bắt buộc | Rails không khởi động |
| `APP_HOST` | host trong link email + bật chặn Host header | Không chặn Host (truy cập bằng IP được) |
| `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD` | gửi mail thật | **Dùng adapter `:test` — mail được soạn nhưng KHÔNG gửi đi đâu** |
| `MAIL_FROM` | địa chỉ gửi | `no-reply@marketingos.local` |
| `AI_PROVIDER`, `OLLAMA_MODEL` | chọn AI | `fake` — mô phỏng offline |

Mặc định an toàn là có chủ đích: triển khai lần đầu **không** âm thầm gửi mail ra
ngoài và **không** âm thầm gọi dịch vụ nào.

Kiểm chứng bằng cách chạy container thật với biến môi trường:

```
delivery: smtp
smtp: {:address=>"smtp.example.net", :port=>587, :user_name=>"u@x.vn", :authentication=>:plain}
raise_errors: true
hosts: ["marketing.congty.vn", ".marketing.congty.vn"]
mail from: no-reply@congty.vn
url host: {:host=>"marketing.congty.vn", :protocol=>"https"}
```

Và khi không khai SMTP: `mailer delivery: test` — đúng như thiết kế.

---

## Một cái bẫy đã chặn trước

`.env.example` có `OLLAMA_HOST=http://localhost:11434` cho môi trường dev. Tài liệu
lại bảo `cp .env.example .env.production` — copy nguyên giá trị đó vào Docker thì
`localhost` là chính container app, Ollama không bao giờ gọi được.

`docker-compose.prod.yml` cố tình **không** đọc `OLLAMA_HOST` từ env file:

```yaml
OLLAMA_HOST: ${OLLAMA_REMOTE_HOST:-http://ollama:11434}
```

Muốn trỏ sang Ollama ở máy khác thì đặt `OLLAMA_REMOTE_HOST`. Có spec khoá lại
điều này.

---

## Kết quả chạy thật

Dựng lại stack từ số không (`down -v` rồi `up --build`):

| Bước | Kết quả |
|---|---|
| `docker build` | thành công, image 850 MB |
| Container boot | `Rails 8.0.5.1 boot OK`, `harness 0.1.0`, `queue adapter: solid_queue` |
| Deploy lần đầu | `app Healthy` → `worker Started`, không lỗi |
| Seeds | `↳ Bỏ qua nội dung mẫu do AI (đang dùng provider "ollama")` |
| Worker | Supervisor + Dispatcher + Worker + Scheduler, có `dispatch_due_reminders` |
| `/up` | HTTP 200 |
| Nhãn AI trên giao diện | `Chạy trên máy · qwen2.5:3b` |
| `POST /campaigns/:id/generate` | HTTP 302 sau **0,05 giây** |
| Worker xử lý job | artifact `social_post`, provider `ollama`, 217 ký tự, trạng thái `draft` |
| Thông báo | `ai_draft_ready` |
| Audit | `AiRun: script_draft \| ollama \| qwen2.5:3b`; `AiCall: method=internal latency=16871ms` |

Nội dung worker thật sinh ra:

> Glow Cosmetics đang chuẩn bị cho một sự thay đổi lớn trong năm nay. Chúng tôi rất
> vui khi tiết lộ teaser của nhận diện mới sắp ra mắt vào mùa Thu Đông. Hãy cùng đón
> chờ những thông điệp mạnh mẽ và tinh tế hơn từ Glow!

Lưu ý: `worker` xử lý mất ~17 giây trong khi request web chỉ 0,05 giây — đúng như
kiến trúc chạy nền đã làm ở Phase 3.

---

## Spec mới (10 ví dụ) — `spec/deploy_readiness_spec.rb`

Khoá lại từng lỗi ở trên để không tái diễn:

- Gemfile không có đường dẫn tuyệt đối kiểu `X:/`; harness vendored load được.
- Dockerfile dùng `COPY vendor/ ./vendor/`, không dùng dạng glob.
- **Seeds không gọi model thật và không ném lỗi khi AI chưa sẵn sàng** — chạy thật
  `load db/seeds.rb` với provider `ollama` và workflow bị stub để raise.
- Seeds vẫn tạo đủ dữ liệu nghiệp vụ khi bỏ qua phần AI.
- `production.rb` không hard-code `example.com`; chưa khai SMTP thì dùng `:test`.
- compose có `worker` chạy `./bin/jobs`; không đọc `OLLAMA_HOST` từ env file;
  **không publish cổng 11434**.

---

---

# Phần 2 — Đã triển khai thật lên VPS Hostinger

Máy chủ: `187.77.127.200` (`srv1864601`, Ubuntu 24.04.4, 8 vCPU, 31 GB RAM, 387 GB đĩa).

URL đang chạy: **https://187-77-127-200.sslip.io** (HTTPS thật, Let's Encrypt)
Dự phòng: `http://187.77.127.200`

## VPS này KHÔNG trống — đang chạy 4 app thật

Khảo sát trước khi làm bất cứ điều gì:

| Stack | Container |
|---|---|
| Reverse proxy | `edge-caddy` — **giữ cổng 80, 443, 3201** |
| CareBridge | `cb-app` (127.0.0.1:3200), `cb-postgres` — domain `itmmomo.com` |
| Kaori Dict | `kd-app` (127.0.0.1:3202), `kd-mt`, `kd-asr`, `kd-asr2`, `kd-asr-stream`, `kd-ollama` |
| Natural Beauty | `natural-beauty-app-1/2/3`, `nb-redis`, `nb-postgres` — cổng 3201 |

Điều này đổi hoàn toàn cách triển khai. Hai quyết định quan trọng:

**1. Không được bind cổng 80.** `docker-compose.prod.yml` ban đầu có
`ports: "${APP_PORT:-80}:80"` → sẽ tranh cổng với `edge-caddy` và làm sập cả 4 app.
Đã sửa thành `"${APP_BIND:-127.0.0.1}:${APP_PORT:-3080}:80"` — mặc định chỉ bind
localhost, đúng cho VPS có proxy. Trên VPS này dùng cổng `3203` (3200 và 3202 đã có chủ).

**2. Chạy Ollama riêng, không dùng chung `kd-ollama`.** Dùng chung sẽ tiết kiệm
RAM nhưng `kd-ollama` bị giới hạn 8 GB và đang phục vụ Kaori Dict; nạp thêm model
4,7 GB của mình vào đó có thể gây OOM cho **app của người khác đang chạy thật**.
Đổi lại 4,8 GB RAM (còn thừa 16 GB) để cô lập hoàn toàn.

## Model: qwen3 KHÔNG dùng được

`kd-ollama` có sẵn `qwen3:8b` và `qwen3:4b`. Dùng lại sẽ khỏi tải 4,7 GB. Nhưng thử
thật thì thất bại:

```json
{"model":"qwen3:4b","response":"","thinking":"Okay, let's see. The user wants me to
translate the JSON string into Vietnamese...","done_reason":"length"}
```

Dòng `qwen3` bật chế độ *thinking* mặc định: toàn bộ token đi vào trường `thinking`,
còn `response` — đúng cái trường mà adapter của harness đọc — **rỗng**. Cộng thêm
`qwen3:8b` hết 280 giây vẫn chưa trả kết quả khi nạp nguội.

Kết luận: tải `qwen2.5:7b` (đã kiểm chứng ở Phase 3) vào Ollama riêng của MarketingOS.

## Sửa Caddy an toàn (4 app đang chạy thật)

Caddyfile dùng chung ở `/srv/proxy/Caddyfile`, tổ chức theo "mỗi dự án một khối".
Quy trình đã áp dụng:

1. Sao lưu: `cp -a Caddyfile Caddyfile.bak.$(date +%F-%H%M%S)`
2. Thêm khối mới dùng **host matcher theo IP** (`http://187.77.127.200`) — chọn cách
   này vì nó **không cần publish cổng mới**, nên không phải tạo lại container
   `edge-caddy` (tạo lại sẽ làm rớt cả 4 app trong vài giây).
3. `caddy validate` → **"Valid configuration"**
4. Chỉ khi validate sạch mới `caddy reload` (nạp êm, không rớt kết nối).
5. Kiểm tra lại từng app cũ.

Kết quả sau reload — không app nào bị ảnh hưởng:

| Kiểm tra | Kết quả |
|---|---|
| `edge-caddy /_health` | 200 |
| `itmmomo.com` (CareBridge) | 308 (chuyển HTTPS, bình thường) |
| Cổng 3201 (Natural Beauty) | 307 (chuyển hướng, bình thường) |
| `187.77.127.200/up` (MarketingOS) | 200 |

## Kết quả đo thật trên VPS

| Kiểm tra | Kết quả |
|---|---|
| Build image trên VPS | thành công |
| Deploy lần đầu | `app Healthy` → `worker Started`, không lỗi |
| Seeds | bỏ qua phần AI đúng như thiết kế (model chưa tải lúc đó) |
| Truy cập từ internet | `http://187.77.127.200/login` → 200, tiếng Việt |
| Smoke test 24 trang (vi + en) | **0 lỗi**, mỗi trang **~0,2 giây** |
| Nhãn AI | `Chạy trên máy · qwen2.5:7b` |
| `POST /generate` | 302 sau **0,25 giây** (chạy nền) |
| Worker sinh nội dung | 102 ký tự tiếng Việt, trạng thái `draft` |
| Audit | `AiRun: script_draft \| ollama \| qwen2.5:7b`; `AiCall: method=internal latency=48039ms` |
| RAM: app / worker / ollama | 130 MB / 207 MB / 4,8 GB |
| RAM VPS còn lại | 16 GB |

Nội dung AI thật sinh ra trên VPS:

> 🌟 Glow Cosmetics sắp có diện mạo mới! 🌟 Hãy cùng chờ đón sự bất ngờ trong Q4 nhé! 🔑 #GlowRebrandTeaser

Chênh lệch **0,25 giây (web) so với 48 giây (worker)** cho thấy kiến trúc chạy nền
ở Phase 3 là bắt buộc, không phải tối ưu cho vui.

## HTTPS — đã có, không cần mua tên miền

Truy cập bằng IP thuần bị lỗi trên trình duyệt: Chrome/Edge **tự nâng cấp sang
HTTPS**, mà một địa chỉ IP thì không thể có chứng chỉ Let's Encrypt. `curl` qua
HTTP vẫn 200 nên lỗi này không lộ ra khi test bằng dòng lệnh.

Cách giải quyết không tốn tiền: dùng DNS wildcard `sslip.io` — `187-77-127-200.sslip.io`
phân giải sẵn về `187.77.127.200`, và vì nó là **tên miền thật** nên Caddy xin được
chứng chỉ bình thường.

```
187-77-127-200.sslip.io {
	reverse_proxy marketingos-app-1:80
	header { Strict-Transport-Security "max-age=31536000" ... }
}
```

Log Caddy sau khi reload:

```
served key authentication  identifier=187-77-127-200.sslip.io challenge=http-01
authorization finalized    authz_status=valid
certificate obtained successfully  issuer=acme-v02.api.letsencrypt.org-directory
```

Kết quả kiểm chứng:

| Đường vào | Kết quả |
|---|---|
| **https://187-77-127-200.sslip.io** (chính) | 200, chứng chỉ hợp lệ (`ssl_verify=0`) |
| http://187.77.127.200 (dự phòng) | 200 |
| Host lạ (`Host: hacker.test`) | 404 — bị Caddy chặn trước khi tới Rails |
| Đăng nhập qua HTTPS | 302 → `https://.../` ✓ |
| Smoke test 26 trang (vi + en) qua HTTPS | **0 lỗi** |
| `itmmomo.com` sau reload lần hai | 200 ✓ |

`APP_HOST=187-77-127-200.sslip.io` + `APP_HOST_EXTRA=187.77.127.200` — bật kiểm tra
Host header mà vẫn giữ được đường vào bằng IP. Link trong email cũng dùng HTTPS.

Có tên miền riêng thì chỉ cần thêm một khối Caddy tương tự với tên miền đó.

## CẢNH BÁO BẢO MẬT — còn lại

**Mật khẩu demo `password123` trên site công khai.** Ai biết địa chỉ đều đăng nhập
được và xem/sửa dữ liệu. Đổi ngay:

```bash
docker compose -f docker-compose.prod.yml -f docker-compose.edge.yml \
  --env-file .env.production exec app bin/rails runner \
  'User.find_by(email: "owner@demo.vn").update!(password: "MatKhauMoi")'
```

Hoặc xoá sạch dữ liệu demo nếu bắt đầu dùng thật.

## Còn lại

- **HTTPS**: chờ tên miền (xem cảnh báo trên).
- **Postgres**: vẫn dùng SQLite cho production (mặc định Rails 8, đủ cho một VPS).
- **Sao lưu tự động**: có lệnh thủ công trong `DEPLOY_VPS.md`, chưa đặt cron.
- **Email**: chưa cấu hình SMTP → mail được soạn nhưng không gửi (Phase 2).
- **Postgres**: `database.yml` vẫn dùng SQLite cho production (mặc định Rails 8,
  đủ cho một VPS một app). `docker-compose.yml` có Postgres cho môi trường
  production-like nhưng `database.yml` chưa trỏ vào — đổi khi thật sự cần nhiều máy.
- **Sao lưu tự động**: tài liệu có lệnh sao lưu thủ công, chưa có cron.
