import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.buttonTarget.setAttribute("aria-expanded", !this.panelTarget.hidden)
  }

  toggle() {
    const open = this.panelTarget.hidden
    this.panelTarget.hidden = !open
    this.buttonTarget.setAttribute("aria-pressed", open)
    this.buttonTarget.setAttribute("aria-expanded", open)
  }
}
