import { Controller } from "@hotwired/stimulus"
import { clearSelection, getTimes, publish, spanSelection } from "helpers/linked_selection"
import { parseTime } from "helpers/time"

const DAY_MS = 86400000

export default class extends Controller {
  disconnect() {
    clearSelection()
  }

  select(event) {
    const { from, to } = event.currentTarget.dataset
    publish(spanSelection(getTimes(), parseTime(from).getTime(), parseTime(to).getTime() + DAY_MS, "streak"))
  }

  clear() {
    clearSelection()
  }
}
