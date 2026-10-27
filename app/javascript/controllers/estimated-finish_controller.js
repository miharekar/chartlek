import { Controller } from "@hotwired/stimulus"
import { finishRow, nextIndex } from "helpers/estimated_finish"

export default class extends Controller {
  static targets = ["time", "label", "pace"]
  static values = { finishes: Array, index: { type: Number, default: 0 } }

  next() {
    this.indexValue = nextIndex(this.indexValue, this.finishesValue.length)
  }

  indexValueChanged() {
    const { label, time, pace } = finishRow(this.finishesValue[this.indexValue])
    this.#write(this.timeTarget, time)
    this.#write(this.labelTarget, label)
    this.#write(this.paceTarget, pace)
  }

  #write(target, text) {
    if (target.textContent !== text) target.textContent = text
  }
}
