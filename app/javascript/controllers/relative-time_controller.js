import { Controller } from "@hotwired/stimulus"
import { TICK_MS, timeAgoWords } from "helpers/live_refresh"

export default class extends Controller {
  connect() {
    this.timer = setInterval(() => this.tick(), TICK_MS)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const words = timeAgoWords((Date.now() - Date.parse(this.element.dateTime)) / 1000)
    if (words) this.element.textContent = words
  }
}
