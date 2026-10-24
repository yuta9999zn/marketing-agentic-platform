# Triển khai MarketingOS lên VPS

Hướng dẫn cho **một VPS Linux** chạy Docker. Toàn bộ stack: web + worker + AI nội bộ.

> **Đã kiểm chứng thật, không phải lý thuyết.** Toàn bộ stack này đã được build và
> chạy đầy đủ trên Docker (Linux container) trước khi viết tài liệu: image build
> thành công (850 MB), `app` khỏe, `worker` chạy Solid Queue, `ollama` sinh nội dung
> tiếng Việt thật qua network nội bộ. Chi tiết kết quả đo: `docs/DEPLOY_REPORT.md`.

---

## 1. Chọn cấu hình VPS — đọc phần này trước

Yếu tố quyết định giá là **có chạy AI trên chính VPS hay không**.

### Nếu chạy AI trên VPS (Ollama)

`qwen2.5:7b` cần khoảng **6 GB RAM** chỉ riêng cho mô hình, chưa tính Rails,
worker và hệ điều hành. Và VPS phổ thông **không có GPU** — suy luận chạy bằng CPU.

Số đo **thật**, không phải ước lượng:

| Tác vụ | Máy dev (20 luồng) | VPS Hostinger 8 vCPU |
|---|---|---|
| Nháp bài social (nạp model + sinh) | 19 giây | **48 giây** |
| Nạp mô hình lần đầu | 87 giây | ~40 giây |
| Tải model `qwen2.5:7b` (4,7 GB) | — | ~2 phút |

RAM thực tế đo trên VPS sau khi model đã nạp:

| Container | RAM |
|---|---|
| `marketingos-app-1` (web) | 130 MB |
| `marketingos-worker-1` | 207 MB |
| `marketingos-ollama-1` (model đã nạp) | **4,8 GB** |

Nghĩa là Rails gần như không tốn gì; **toàn bộ chi phí nằm ở mô hình AI**.

**Khuyến nghị tối thiểu nếu chạy Ollama:** 4 vCPU, 8 GB RAM, 40 GB đĩa.
Dưới mức đó mô hình sẽ bị hệ điều hành kill vì hết RAM.

Trang web (không gọi AI) phản hồi **~0,2 giây** — nhanh, vì AI đã tách sang worker.

**VPS nhỏ (2 vCPU / 4 GB):** dùng mô hình nhỏ hơn:

```
OLLAMA_MODEL=qwen2.5:3b     # ~2 GB, nhanh hơn khoảng 2 lần, chất lượng thấp hơn
```

Đừng dùng `llama3.2:1b` — đã đo, nó không trả nổi JSON đúng định dạng.

### Nếu KHÔNG chạy AI trên VPS

Ba lựa chọn, app hỗ trợ cả ba mà không phải sửa code:

| Cách | Cấu hình | Ghi chú |
|---|---|---|
| Tắt AI | `AI_PROVIDER=fake` | App chạy đầy đủ, chỉ AI là mô phỏng. VPS 1 vCPU / 1 GB là đủ |
| Ollama ở máy khác | `AI_PROVIDER=ollama` + `OLLAMA_HOST=http://<ip>:11434` | Phải bảo vệ cổng đó, đừng mở ra internet |
| API bên ngoài | `AI_PROVIDER=anthropic` + `ANTHROPIC_API_KEY` + `AI_EXTERNAL_ENABLED=true` | Nhanh nhất, chất lượng cao nhất, nhưng **dữ liệu khách hàng rời khỏi máy** và cần tick consent từng lần |

VPS chỉ chạy Rails (không AI): **1 vCPU, 1 GB RAM, 20 GB đĩa** là chạy được.

---

## 2. Chuẩn bị máy chủ

```bash
# Ubuntu 22.04/24.04
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker

git clone <repo> marketingos && cd marketingos
```

## 3. Cấu hình

```bash
cp .env.example .env.production
```

Sửa `.env.production`:

```bash
# BẮT BUỘC — sinh bằng: docker run --rm marketingos:latest bin/rails secret
SECRET_KEY_BASE=<chuỗi dài ngẫu nhiên>

# Tên miền hoặc IP. Bỏ trống thì tắt kiểm tra Host header (chỉ nên dùng khi test).
APP_HOST=marketing.congty.vn

# AI: fake | ollama | anthropic | openai
AI_PROVIDER=ollama
OLLAMA_MODEL=qwen2.5:7b
# Trong docker compose, Ollama là "ollama" chứ KHÔNG phải localhost
OLLAMA_HOST=http://ollama:11434

# Email giao dịch. Chưa khai SMTP_HOST thì mail được soạn nhưng KHÔNG gửi đi đâu.
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=ban@gmail.com
SMTP_PASSWORD=<app password, KHÔNG phải mật khẩu đăng nhập>
MAIL_FROM=no-reply@congty.vn
```

`RAILS_MASTER_KEY` hoặc `SECRET_KEY_BASE`: cần một trong hai. Dùng
`SECRET_KEY_BASE` đơn giản hơn vì không phải mang `config/master.key` lên máy chủ.

## 4. Khởi chạy

```bash
# Có AI nội bộ
docker compose -f docker-compose.prod.yml --env-file .env.production --profile ai up -d --build

# Không có AI nội bộ (AI_PROVIDER=fake hoặc dùng API ngoài)
docker compose -f docker-compose.prod.yml --env-file .env.production up -d --build
```

Tải mô hình (một lần, vài phút):

```bash
docker compose -f docker-compose.prod.yml exec ollama ollama pull qwen2.5:7b
```

Tạo dữ liệu demo (tuỳ chọn):

```bash
docker compose -f docker-compose.prod.yml exec app bin/rails db:seed
```

## 5. Kiểm tra sau khi dựng

```bash
# Web sống chưa
curl -fsS http://localhost/up && echo OK

# Worker có chạy không — THIẾU CÁI NÀY thì bản nháp AI nằm mãi trong hàng đợi
docker compose -f docker-compose.prod.yml ps worker
docker compose -f docker-compose.prod.yml logs worker | tail -20

# Ollama có mô hình chưa
docker compose -f docker-compose.prod.yml exec ollama ollama list
```

Đăng nhập, vào một campaign, xem nhãn trạng thái AI ở khối trợ lý:

- *"Chạy trên máy · qwen2.5:7b"* → xong.
- *"Chưa tải model"* → chạy lệnh `ollama pull` ở mục 4.
- *"Không kết nối được AI"* → service `ollama` chưa chạy, hoặc `OLLAMA_HOST` sai
  (nhớ là `http://ollama:11434`, không phải `localhost`).

## 6. VPS đã có reverse proxy sẵn (nhiều app trên một máy)

Nếu máy chủ đã có Caddy/nginx trong container giữ cổng 80/443 và các app dùng
chung một network external tên `edge` (mô hình đang chạy trên VPS này), thì:

```bash
docker compose -f docker-compose.prod.yml -f docker-compose.edge.yml \
  --env-file .env.production --profile ai up -d --build
```

`docker-compose.edge.yml` gắn container web vào network `edge` để proxy gọi được
bằng tên container. Trong `.env.production` giữ `APP_BIND=127.0.0.1` và chọn một
cổng còn trống (ví dụ `APP_PORT=3203`) — **tuyệt đối không** đặt `APP_PORT=80` vì
sẽ tranh cổng với proxy và làm sập mọi app khác.

Khối Caddy thêm vào Caddyfile dùng chung:

```
ten-mien-cua-ban.com {
	reverse_proxy marketingos-app-1:80
}
```

Chưa có tên miền thì tạm dùng chính IP máy chủ (`http://<ip> { ... }`).

**Bắt buộc validate trước khi reload** — sai cú pháp sẽ làm chết cả proxy:

```bash
cp -a /srv/proxy/Caddyfile /srv/proxy/Caddyfile.bak.$(date +%F-%H%M%S)
docker compose -f /srv/proxy/docker-compose.yml exec caddy caddy validate --config /etc/caddy/Caddyfile
# chỉ khi thấy "Valid configuration":
docker compose -f /srv/proxy/docker-compose.yml exec caddy caddy reload --config /etc/caddy/Caddyfile
```

`caddy reload` là nạp lại êm, không rớt kết nối và không cần restart container.

## 7. Đo tốc độ thật trên VPS của bạn

```bash
docker compose -f docker-compose.prod.yml exec ollama \
  sh -c 'time ollama run qwen2.5:7b "Viết một câu quảng cáo cà phê."'
```

Nếu quá 2 phút cho một câu, hãy đổi sang `qwen2.5:3b` hoặc dùng API bên ngoài.

**Đừng dùng model dòng `qwen3`**: chúng bật chế độ "thinking" mặc định, đổ toàn bộ
kết quả vào trường `thinking` và để `response` rỗng — app sẽ không nhận được gì.
Đã kiểm chứng: `qwen3:4b` trả `"response":""` với `done_reason:"length"`.

## 8. Vận hành

```bash
# Cập nhật phiên bản mới
git pull
docker compose -f docker-compose.prod.yml --env-file .env.production up -d --build

# Sao lưu (SQLite + file tải lên nằm chung một volume)
docker run --rm -v marketingos_storage:/data -v $PWD:/backup alpine \
  tar czf /backup/backup-$(date +%F).tar.gz -C /data .

# Xem log
docker compose -f docker-compose.prod.yml logs -f app worker
```

### HTTPS khi CHƯA có tên miền

Đừng dùng địa chỉ IP thuần: Chrome/Edge **tự nâng cấp sang HTTPS**, mà IP thì không
thể có chứng chỉ Let's Encrypt → trình duyệt báo lỗi. (`curl http://<ip>` vẫn 200 nên
lỗi này không lộ ra khi test bằng dòng lệnh — rất dễ tưởng là đã xong.)

Cách giải quyết miễn phí: DNS wildcard `sslip.io`. Địa chỉ `<ip-gạch-nối>.sslip.io`
phân giải sẵn về đúng IP đó, và vì là **tên miền thật** nên Caddy xin được chứng chỉ:

```
187-77-127-200.sslip.io {
	reverse_proxy marketingos-app-1:80
	header { Strict-Transport-Security "max-age=31536000" }
}
```

Đổi `187-77-127-200` thành IP của bạn với dấu chấm thay bằng gạch nối. Reload Caddy,
đợi ~20 giây là có HTTPS. `nip.io` cũng hoạt động tương tự.

Trong `.env.production` khai cả hai để giữ được đường vào bằng IP:

```
APP_HOST=187-77-127-200.sslip.io
APP_HOST_EXTRA=187.77.127.200
```

Có tên miền riêng thì thêm một khối Caddy với tên miền đó — Caddy tự lo chứng chỉ.

---

## Những điểm dễ sai

| Triệu chứng | Nguyên nhân |
|---|---|
| Bấm tạo nháp AI, đợi mãi không thấy gì | Service `worker` không chạy |
| *"Không kết nối được AI"* | `OLLAMA_HOST` để `localhost` thay vì `http://ollama:11434` |
| Container ollama bị kill liên tục | VPS thiếu RAM — đổi sang model 3b hoặc nâng VPS |
| Mail không tới | Chưa khai `SMTP_HOST` → app dùng adapter test, cố tình không gửi |
| Lỗi Blocked host | `APP_HOST` không khớp tên miền đang truy cập |
| Build lỗi ở bước bundle | Thiếu `vendor/gems/cdfl_harness` — chạy `bin/sync_harness` rồi commit |

## Bảo mật

- **Không** publish cổng 11434 ra internet. Trong `docker-compose.prod.yml`
  Ollama chỉ dùng `expose`, không `ports` — chỉ container khác trong stack gọi được.
- `.env.production` chứa bí mật: `chmod 600`, không commit.
- Ollama chạy nội bộ nên dữ liệu khách hàng không rời khỏi VPS. Chuyển sang
  `anthropic`/`openai` thì dữ liệu **có** rời đi — cần bật `AI_EXTERNAL_ENABLED`
  và tick consent từng lần, đúng thiết kế double-gate.
