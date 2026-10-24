# Ai::Providers

Tất cả provider thật (Anthropic / OpenAI / Ollama / Fake) do harness `cdfl_harness`
cung cấp và được `Ai::Gateway` quản lý. Không có adapter nào khác được phép gọi
model trực tiếp — mọi lời gọi phải đi qua `CDFLHarness::Gateway::Client`.

Thứ bậc cấu hình (ENV, xem `.env.example`):
- `AI_PROVIDER` = `fake` (mặc định) | `ollama` | `anthropic` | `openai`
- `AI_EXTERNAL_ENABLED` = `true` mới mở master-switch cho provider ngoài.
- Với provider ngoài, từng lần gọi trong UI vẫn phải tick "consent gửi dữ liệu ra ngoài"
  thì router của harness mới không downgrade về local.

Để thêm provider mới (ví dụ Vertex): subclass `CDFLHarness::Gateway::Adapters::Base`
rồi gán vào `config.adapter_override` trong `Ai::Gateway#build_config`.
