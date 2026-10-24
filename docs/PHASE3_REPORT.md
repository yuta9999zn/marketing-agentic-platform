# Phase 3 — AI thật chạy trên máy (Ollama)

Ngày: 2026-08-17. Trạng thái: **193/193 RSpec pass** (133 cũ + 60 mới),
smoke test HTTP 28 lượt tải trang ở cả `vi` và `en` — 0 lỗi.
Đã chạy thật với Ollama, không phải mô phỏng.

---

## Cấu hình đang dùng

| | |
|---|---|
| Provider | `ollama` — chạy trên chính máy này |
| Model | `qwen2.5:7b` (4.7 GB, tải về trong phase này) |
| Host | `http://localhost:11434` |
| Dữ liệu ra ngoài | **Không.** Harness coi ollama là `internal` |

Bật bằng `.env`:

```
AI_PROVIDER=ollama
OLLAMA_MODEL=qwen2.5:7b
OLLAMA_HOST=http://localhost:11434
```

### Vì sao phải tải model mới

Máy đã có `llama3.2:1b`, nhưng **1.2 tỷ tham số là quá nhỏ** cho công việc này:
đo thực tế cho thấy nó không trả nổi JSON đúng schema với prompt tiếng Việt
(thất bại cả sau vòng repair của harness). `qwen2.5:7b` viết tiếng Việt tự nhiên
và bám schema ổn định — cùng dòng model mà harness đặt làm mặc định.
`bge-m3` là model embedding, không sinh văn bản được.

### Vì sao ollama KHÔNG cần consent gửi ra ngoài

Đây là điểm thiết kế quan trọng. Harness phân biệt `internal` và `external`:
`Adapters::Ollama#external?` trả `false`, nên router không bao giờ coi nó là lời
gọi ra ngoài. Double-gate (`AI_EXTERNAL_ENABLED` + tick consent) tồn tại để bảo vệ
dữ liệu khách hàng khỏi bị gửi tới bên thứ ba — với ollama thì dữ liệu **không rời
khỏi máy**, nên bắt tick consent là vô nghĩa và gây phiền.

`AdapterFactory` phân ba nhóm rõ ràng: `fake` → `local` → `external`, chỉ nhóm
cuối mới cần `org.ai_external_enabled`. Có test khoá invariant này
(bật `ai_external_enabled=true` mà `config.external?` vẫn phải là `false`).

---

## 1. Tác vụ AI chuyển sang chạy nền

**Đây là thay đổi kiến trúc lớn nhất của phase.** Đo thực tế trên máy này:

| Tác vụ | Model nguội | Model đã nạp |
|---|---|---|
| Nháp kịch bản (JSON schema) | 87 s | 19 s |
| Dịch một đoạn ngắn | 14 s | 6 s |
| Soạn prompt ảnh | — | 48 s |

Chạy đồng bộ trong request web nghĩa là người dùng ngồi nhìn trang treo 20-90 giây.
Nên:

- `AiDraftJob`, `ArtifactTranslationJob`, `ImagePromptJob` — chạy nền, xong thì tạo
  **notification** cho người dùng (`ai_draft_ready`, `translation_ready`,
  `image_prompt_ready`, và các biến thể `_failed`).
- Job **không bao giờ ném lỗi ra ngoài**: thất bại thành notification để người dùng
  nhìn thấy, không im lặng.
- `config.active_job.queue_adapter` ở development đổi từ `:inline` sang `:async` —
  `:inline` sẽ chạy job ngay trong request, đúng cái ta cần tránh.
- `Ai::Gateway.synchronous?` quyết định: provider `fake` chạy ngay (tức thì),
  provider thật đẩy sang job. Nhờ vậy toàn bộ test cũ giữ nguyên hành vi.

Đo lại sau khi sửa: request `POST /campaigns/:id/generate` trả về sau **0.5 giây**.

## 2. Kiểm tra AI có sẵn sàng không

`Ai::Availability` hỏi `/api/tags` của Ollama (timeout 3 giây, cache 30 giây) và
trả về một trong: sẵn sàng / không kết nối được / chưa tải model / thiếu API key.
**Không bao giờ raise** — mọi lỗi mạng thành trạng thái "không sẵn sàng".

- Giao diện hiện nhãn thật: *"Chạy trên máy · qwen2.5:7b"*, hoặc đỏ *"Không kết nối
  được AI"* — thay cho nhãn `Local · Fake` viết cứng trước đây.
- Controller kiểm tra trước khi xếp job: AI hỏng thì báo ngay, không tạo job rác.

## 3. Dịch bằng mô hình ngôn ngữ

`Providers::TranslationLlmAdapter` thay từ điển cứng vi→en.

- Dùng `generate_text` (văn bản tự do) chứ không phải `generate_structured`: dịch
  thuật không cần JSON, và ép model trả JSON làm hỏng xuống dòng/emoji.
- Xử lý hai tật của model: câu dẫn thừa (*"Here is the translation:"*) và bọc kết
  quả trong khối ```` ``` ```` — đều bị bóc.
- Cắt đầu vào ở 6000 ký tự và **nói rõ đã cắt**, không im lặng mất nội dung.

**Một vấn đề chất lượng đã phát hiện và sửa:** bản dịch đầu tiên model tự thêm
`🍵☀️ #SummerSips #ACMECoffee` — nội dung không có trong bản gốc. Đã siết prompt
("TUYỆT ĐỐI KHÔNG thêm hashtag, emoji, câu kêu gọi hành động"), đo lại thì sạch:

```
gốc:  Mùa hè này ACME Coffee ra mắt dòng cold brew mới, giảm 20% cho khách hàng thân thiết.
dịch: This summer, ACME Coffee launches a new cold brew line, offering 20% off to loyal customers.
```

## 4. Dịch nhanh tại chỗ (realtime)

`POST /quick-translate` — dịch một đoạn bất kỳ, **không tạo artifact, không tạo
version**. Đây là công cụ đọc hiểu, không phải bước sản xuất nội dung. Vẫn ghi
`AiRun` để audit đầy đủ.

- Nút "Dịch" trên từng góp ý ở trang campaign, trang nội dung và trang khảo sát.
  Bấm lần hai để ẩn, không gọi lại model.
- Stimulus controller `quick_translate`; dùng `textContent` chứ không `innerHTML`
  — nội dung từ model không được tin.
- Endpoint JSON nên phân quyền **trả 403 JSON**, không redirect (fetch không hiểu
  redirect). Khách được mời chỉ dịch được nội dung của chính campaign mình tham gia.
- Model hỏng → **503 và nói thật**, không trả bản dịch giả.
- Đo thực tế: 6 giây khi model đã nạp.

## 5. Khảo sát + AI phân tích thành insight

Bảng mới `surveys` và `survey_responses`, gắn với campaign.

- Tạo khảo sát ngay trong trang campaign, mỗi dòng một câu hỏi.
- Trạng thái `draft → open → closed`; chỉ nhận phản hồi khi đang `open`.
- Khách hàng được mời vào campaign cũng trả lời được.
- Câu trả lời chỉ giữ đúng khóa câu hỏi của khảo sát — khóa lạ bị loại ở cả tầng
  `params.permit` lẫn model (có test).

`Ai::Workflows::SurveyInsight` đọc phản hồi **thật** và viết bản phân tích:

- Dưới 3 phản hồi → đánh dấu `small_sample`, prompt bắt buộc *"chỉ tóm tắt, tuyệt
  đối không rút kết luận chung"*.
- Prompt cấm bịa số liệu và cấm tạo tỷ lệ phần trăm không đếm được từ dữ liệu —
  đúng tinh thần coverage gate của harness.
- Kết quả là artifact `report` trạng thái `draft`, chờ người duyệt.

Kết quả chạy thật với 3 phản hồi:

```
## Tóm tắt (3 phản hồi)
Khảo sát cho thấy khách hàng có nhiều tiêu chí khác nhau khi chọn quán cà phê...

## Insight
- Cả hai phản hồi 1 và 2 đều đề cập đến việc giá cả là một yếu tố quan trọng.
  Chị Mai sẵn sàng trả khoảng 45 nghìn, trong khi Anh Tuấn chấp nhận 50-60 nghìn.

## Còn thiếu dữ liệu
- Chất lượng phục vụ và trải nghiệm tổng thể chưa được đề cập.
```

## 6. Prompt ảnh — nói thật về giới hạn

**Ollama KHÔNG tạo được ảnh.** `qwen2.5` và `llama3.2` là model văn bản; `bge-m3`
là embedding. Máy này cũng không chạy dịch vụ tạo ảnh nào (đã kiểm tra cổng 7860
của Automatic1111, 8188 của ComfyUI, 5000 — đều không có).

Cái làm được và đã làm: `ImagePromptLlmAdapter` dùng LLM biến vài dòng brief rời
rạc thành prompt ảnh có cấu trúc (chủ thể → bối cảnh → bố cục → ánh sáng → tông màu
→ chất liệu → tâm trạng), đem sang bất kỳ công cụ tạo ảnh nào là dùng được ngay.
LLM hỏng thì vẫn trả gói prompt cơ bản, không làm hỏng thao tác của người dùng.

Muốn ra ảnh thật cần cài thêm một dịch vụ riêng (Stable Diffusion cục bộ qua
Automatic1111 hoặc ComfyUI), hoặc dùng provider ảnh trả phí. **Chưa làm** vì máy
chưa có gì để nối vào và tôi không viết adapter không kiểm chứng được.

---

## Bug thật đã sửa trong phase này

**1. Nội dung rỗng vẫn được lưu thành bản nháp.**
Model trả `content: ""` — hợp lệ theo schema (vẫn là chuỗi) nhưng vô dụng, và app
đã tạo ra một artifact trống. Đã thêm `minLength` vào schema (kích hoạt vòng repair
của harness) **và** một chốt chặn trong workflow: content rỗng thì báo lỗi rõ ràng
thay vì lưu bản nháp trống.

**2. Không xoá được artifact có audit AI trỏ tới — lỗi khoá ngoại.**
`ai_runs.output_artifact_id` có khoá ngoại nhưng `Artifact` không khai báo quan hệ
ngược. Hệ quả: **xoá campaign hoặc khách hàng có nội dung do AI tạo sẽ lỗi 500**
(vì `Campaign has_many :artifacts, dependent: :destroy`). Đã thêm
`has_many :ai_runs, dependent: :nullify` — dòng audit được giữ lại, chỉ bỏ con trỏ.
Audit không được phép biến mất.

**3. Audit ghi sai tên model.**
Bốn workflow ghi cứng `model: "fake-deterministic"` vào `AiRun` kể cả khi đang chạy
model thật. Đã đổi sang `gw.model_label` — giờ ghi đúng `qwen2.5:7b`.

**4. Model trả kết quả bằng tiếng Anh cho prompt tiếng Việt.**
`missing_data` trả về `["Image URL for the post", ...]`. Đã bổ sung yêu cầu tường
minh "Viết TOÀN BỘ bằng tiếng Việt, kể cả missing_data".

---

## Kiểm chứng bằng chạy thật

Không phải mô phỏng — đây là output thật từ `qwen2.5:7b` qua giao diện web:

| Kiểm tra | Kết quả |
|---|---|
| Nhãn trạng thái AI | `Chạy trên máy · qwen2.5:7b` |
| Nháp bài social (chạy nền) | request trả về sau 0.5 s; nội dung tiếng Việt 108 ký tự |
| `AiRun` sau khi sinh | `workflow=script_draft provider=ollama model=qwen2.5:7b` |
| `AiCall` sau khi sinh | `method=internal repaired=false latency=16407ms` |
| Prompt lưu trong metadata | chỉ SHA-256, không có văn bản thô |
| Trạng thái artifact | `draft` — vẫn phải qua duyệt |
| Dịch nhanh tiếng Việt→Anh | 6 s, không tự thêm nội dung |
| Phân tích khảo sát 3 phản hồi | trích đúng tên và con số người trả lời đã nói |
| Prompt ảnh | 7 câu mô tả có cấu trúc, ghi rõ "CHƯA phải ảnh" |
| Dịch nhanh sai quyền | 403 JSON |

## Test mới (60 ví dụ)

| File | Nội dung |
|---|---|
| `spec/services/phase3_ollama_gateway_spec.rb` | phân loại provider, ollama không bật cờ external, kiểm tra sẵn sàng không raise |
| `spec/services/phase3_translation_spec.rb` | chọn adapter, bóc câu dẫn/khối code, cấm thêm nội dung, cắt văn bản dài, dịch nhanh không tạo artifact |
| `spec/requests/phase3_survey_spec.rb` | tạo/mở/đóng khảo sát, loại khóa lạ, phân quyền, ngưỡng mẫu nhỏ, prompt cấm bịa số liệu |
| `spec/requests/phase3_quick_translate_spec.rb` | 403/404/422/503 JSON, phạm vi campaign, locale lạ |
| `spec/requests/phase3_async_ai_spec.rb` | provider chậm phải xếp job và KHÔNG chạy AI trong request |
| `spec/jobs/phase3_ai_jobs_spec.rb` | ba job tạo notification khi xong và khi lỗi, không ném ra ngoài |

`spec/support/env_helper.rb` — đặt biến môi trường tạm cho từng ví dụ, luôn khôi phục.

---

## Còn lại

- **Render ảnh thật**: cần cài Stable Diffusion cục bộ hoặc dùng provider trả phí.
- **Email thật** (Phase 2): vẫn là adapter `:test`, cần SMTP/Resend.
- **Tốc độ**: `qwen2.5:7b` mất 19-48 giây cho tác vụ dài trên máy này. Model lớn hơn
  (`qwen2.5:14b`) chất lượng cao hơn nhưng chậm hơn; máy có GPU sẽ nhanh hơn nhiều.
- **Chạy nền ở production**: cần worker Solid Queue (`bin/jobs`). Development dùng
  `:async` trong tiến trình, đủ cho một người dùng.
