import { Controller } from "@hotwired/stimulus"
import { escapeHtml, hideTooltip, isTooltipFor, showTooltipFor } from "helpers/tooltip"

export default class extends Controller {
  static values = { text: String }

  disconnect() {
    this.hide()
  }

  hover(event) {
    if (event.pointerType === "mouse") this.show()
  }

  focus() {
    if (this.element.matches(":focus-visible")) this.show()
  }

  show() {
    showTooltipFor(escapeHtml(this.textValue), this.element)
  }

  hide() {
    if (isTooltipFor(this.element)) hideTooltip()
  }
}
