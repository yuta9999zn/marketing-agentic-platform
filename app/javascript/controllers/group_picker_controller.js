import { Controller } from "@hotwired/stimulus"

// Chọn nhóm khi lên kế hoạch chia sẻ: lọc theo tên/nhãn, chọn tất cả nhóm
// đang hiện, đếm số nhóm đã chọn.
export default class extends Controller {
  static targets = ["query", "item", "count"]

  connect() { this.update() }

  filter() {
    const q = this.queryTarget.value.trim().toLowerCase()
    this.itemTargets.forEach((item) => {
      const hay = (item.dataset.search || "").toLowerCase()
      item.hidden = q.length > 0 && !hay.includes(q)
    })
  }

  selectVisible(event) {
    event.preventDefault()
    this.itemTargets.filter((i) => !i.hidden).forEach((i) => {
      const box = i.querySelector("input[type=checkbox]")
      if (box && !box.disabled) box.checked = true
    })
    this.update()
  }

  clear(event) {
    event.preventDefault()
    this.itemTargets.forEach((i) => {
      const box = i.querySelector("input[type=checkbox]")
      if (box && !box.disabled) box.checked = false
    })
    this.update()
  }

  update() {
    if (!this.hasCountTarget) return
    const n = this.itemTargets.filter((i) => i.querySelector("input[type=checkbox]:checked:not(:disabled)")).length
    this.countTarget.textContent = n
  }
}
