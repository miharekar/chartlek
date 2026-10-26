import { Controller } from "@hotwired/stimulus"
import { escapeHtml, hideTooltip, isTooltipFor, showTooltipFor } from "helpers/tooltip"

export default class extends Controller {
  connect() {
    this.pinned = false
  }

  disconnect() {
    this.hide()
  }

  get showing() {
    return isTooltipFor(this.element)
  }

  show() {
    if (!this.showing) this.pinned = false
    showTooltipFor(escapeHtml(this.element.getAttribute("aria-label")), this.element)
  }

  leave() {
    if (!this.pinned) this.hide()
  }

  toggle() {
    if (this.showing && this.pinned) {
      this.hide()
    } else {
      this.show()
      this.pinned = true
    }
  }

  outside(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  hide() {
    this.pinned = false
    if (this.showing) hideTooltip()
  }
}
