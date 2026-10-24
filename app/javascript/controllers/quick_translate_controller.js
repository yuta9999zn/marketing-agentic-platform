import { Controller } from "@hotwired/stimulus"

// Dịch nhanh một đoạn văn bản tại chỗ.
//
// Đặt trên phần tử chứa nội dung cần dịch:
//   <div data-controller="quick-translate"
//        data-quick-translate-campaign-id-value="12"
//        data-quick-translate-target-value="en">
//     <p data-quick-translate-target="source">Nội dung tiếng Việt…</p>
//     <button data-action="quick-translate#translate">Dịch</button>
//     <div data-quick-translate-target="output" hidden></div>
//   </div>
export default class extends Controller {
  static targets = ["source", "output", "button"]
  static values = {
    campaignId: String,
    target: { type: String, default: "en" },
    url: { type: String, default: "/quick-translate" },
    loading: { type: String, default: "Đang dịch…" }
  }

  translate(event) {
    event.preventDefault()
    if (this.busy) return

    const text = this.sourceTarget.innerText.trim()
    if (!text) return

    // Bấm lần hai để ẩn bản dịch đã có — không gọi lại model.
    if (this.hasOutputTarget && this.outputTarget.dataset.loaded === "true") {
      this.outputTarget.hidden = !this.outputTarget.hidden
      return
    }

    this.busy = true
    const label = this.hasButtonTarget ? this.buttonTarget.textContent : null
    if (this.hasButtonTarget) {
      this.buttonTarget.textContent = this.loadingValue
      this.buttonTarget.disabled = true
    }

    const body = new FormData()
    body.append("text", text)
    body.append("target_locale", this.targetValue)
    if (this.campaignIdValue) body.append("campaign_id", this.campaignIdValue)

    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrfToken, "Accept": "application/json" },
      body
    })
      .then((r) => r.json().catch(() => ({ ok: false, error: "Máy chủ không trả về kết quả hợp lệ." })))
      .then((data) => {
        if (data.ok) {
          this.show(data.text, data.truncated)
        } else {
          this.show(data.error || "Dịch không thành công.", false, true)
        }
      })
      .catch(() => this.show("Không kết nối được tới máy chủ dịch.", false, true))
      .finally(() => {
        this.busy = false
        if (this.hasButtonTarget) {
          this.buttonTarget.textContent = label
          this.buttonTarget.disabled = false
        }
      })
  }

  show(text, truncated, isError = false) {
    if (!this.hasOutputTarget) return
    this.outputTarget.hidden = false
    this.outputTarget.classList.toggle("qt-error", isError)
    // textContent chứ không innerHTML: nội dung đến từ model, không tin được.
    this.outputTarget.textContent = truncated ? `${text}\n\n(Đã cắt bớt phần cuối.)` : text
    this.outputTarget.dataset.loaded = isError ? "false" : "true"
  }

  get csrfToken() {
    const el = document.querySelector('meta[name="csrf-token"]')
    return el ? el.content : ""
  }
}
