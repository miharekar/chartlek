import { Controller } from "@hotwired/stimulus"
import { noMouseFocus, rovingTarget } from "helpers/roving"
import { hideTooltip, isTooltipFor, moveTooltip, showTooltipFor, tooltipHtml } from "helpers/tooltip"

export default class extends Controller {
  static targets = ["segment"]

  connect() {
    this.current = 0
  }

  disconnect() {
    this.#dismiss()
  }

  press(event) {
    noMouseFocus(event)
  }

  enter(event) {
    this.#show(event.currentTarget)
    if (document.activeElement !== event.currentTarget) moveTooltip(event)
  }

  move(event) {
    if (isTooltipFor(event.currentTarget) && document.activeElement !== event.currentTarget) moveTooltip(event)
  }

  leave(event) {
    if (document.activeElement === event.currentTarget) return
    if (isTooltipFor(event.currentTarget)) hideTooltip()
  }

  focus(event) {
    this.current = this.segmentTargets.indexOf(event.currentTarget)
    this.segmentTargets.forEach((segment, index) => segment.tabIndex = index === this.current ? 0 : -1)
    this.#show(event.currentTarget)
  }

  blur(event) {
    if (isTooltipFor(event.currentTarget)) hideTooltip()
  }

  key(event) {
    if (event.key === "Escape" && isTooltipFor(event.currentTarget)) return hideTooltip()
    const target = rovingTarget(event.key, this.current, this.segmentTargets.length - 1)
    if (target == null) return
    event.preventDefault()
    this.segmentTargets[target].focus()
  }

  #show(segment) {
    const { title, rows } = segment.dataset
    showTooltipFor(tooltipHtml(title, JSON.parse(rows)), segment)
  }

  #dismiss() {
    if (this.segmentTargets.some(isTooltipFor)) hideTooltip()
  }
}
