import { Controller } from "@hotwired/stimulus"

// Tooltip hover cho biểu đồ SVG của dashboard — không thư viện ngoài.
export default class extends Controller {
  static targets = ["col", "tip"]

  connect() {
    this.colTargets.forEach((col) => {
      col.addEventListener("mouseenter", () => this.show(col))
      col.addEventListener("mouseleave", () => this.hide())
    })
  }

  show(col) {
    if (!this.hasTipTarget) return
    this.colTargets.forEach((c) => c.classList.remove("is-active"))
    col.classList.add("is-active")
    this.tipTarget.innerHTML = `<b>${col.dataset.date}</b><br>${col.dataset.values}`
    this.tipTarget.hidden = false
    const box = this.element.getBoundingClientRect()
    const rect = col.getBoundingClientRect()
    let left = rect.left - box.left + rect.width / 2
    left = Math.min(Math.max(left, 70), box.width - 70)
    this.tipTarget.style.left = `${left}px`
  }

  hide() {
    if (!this.hasTipTarget) return
    this.tipTarget.hidden = true
    this.colTargets.forEach((c) => c.classList.remove("is-active"))
  }
}
