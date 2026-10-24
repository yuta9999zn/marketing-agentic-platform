import { Controller } from "@hotwired/stimulus"

// Nút "Sao chép". Nguồn chép, theo thứ tự ưu tiên:
//   1. data-clipboard-text-param trên chính nút (vd link bài Page)
//   2. target `source` (textarea nội dung, có thể người dùng vừa sửa)
//   3. data-clipboard-text-value trên phần tử controller
// Hiện nhãn "Đã chép ✓" trên nút trong 2 giây.
export default class extends Controller {
  static targets = ["source"]
  static values = { text: String, done: { type: String, default: "Copied ✓" } }

  async copy(event) {
    event.preventDefault()
    const button = event.currentTarget
    const param = event.params && event.params.text
    const text = param ? String(param) : (this.hasSourceTarget ? this.sourceTarget.value : this.textValue)
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text)
      } else {
        this.fallbackCopy(text)
      }
      this.flash(button, this.doneValue)
    } catch (_e) {
      this.fallbackCopy(text)
      this.flash(button, this.doneValue)
    }
  }

  fallbackCopy(text) {
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.appendChild(area)
    area.select()
    document.execCommand("copy")
    area.remove()
  }

  flash(button, label) {
    if (!button.dataset.originalLabel) button.dataset.originalLabel = button.innerHTML
    button.innerHTML = label
    button.classList.add("is-copied")
    clearTimeout(button._copyTimer)
    button._copyTimer = setTimeout(() => {
      button.innerHTML = button.dataset.originalLabel
      button.classList.remove("is-copied")
    }, 2000)
  }
}
