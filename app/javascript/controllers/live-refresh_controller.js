import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { linkStep, shouldRefresh } from "helpers/live_refresh"

const FIELDS = "form :is(input:not([type=hidden], [type=submit], [type=button], [type=image]), textarea, select)"

export default class extends Controller {
  static targets = ["stream"]

  streamTargetConnected(stream) {
    this.link = { seen: false, dropped: false }
    this.observer = new MutationObserver(() => this.watch(stream))
    this.observer.observe(stream, { attributes: true, attributeFilter: ["connected"] })
    this.watch(stream)
  }

  streamTargetDisconnected() {
    this.observer?.disconnect()
  }

  watch(stream) {
    const { refresh, ...link } = linkStep(this.link, stream.hasAttribute("connected"))
    this.link = link
    if (shouldRefresh(refresh, Boolean(document.querySelector(FIELDS)))) Turbo.session.refresh(document.baseURI)
  }
}
