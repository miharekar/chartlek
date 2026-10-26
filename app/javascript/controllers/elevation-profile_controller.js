import { Controller } from "@hotwired/stimulus"
import { bisector } from "d3-array"
import { scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { line } from "d3-shape"
import { formatDistance } from "helpers/formatters"
import { peakPoint, profileDomain, profilePoints } from "helpers/elevation_profile"
import { observeSize } from "helpers/resize"
import { clear, publish, subscribe } from "helpers/run_cursor"
import { hideTooltip, showTooltip, tooltipHtml } from "helpers/tooltip"

const HEIGHT = 70
const PAD = 6
const BY_KM = bisector(point => point.km)

export default class extends Controller {
  static targets = ["chart"]
  static values = { distances: Array, altitudes: Array }

  connect() {
    this.points = profilePoints(this.distancesValue, this.altitudesValue)
    this.svg = select(this.chartTarget).append("svg").attr("class", "block")
    this.unsubscribe = subscribe(distance => {
      this.cursor = distance
      this.#showCursor()
    })
    this.stopObserving = observeSize(this.chartTarget, ({ width }) => {
      this.width = width
      this.draw()
    })
  }

  disconnect() {
    this.stopObserving()
    this.unsubscribe()
    hideTooltip()
    this.svg.remove()
    clear()
  }

  draw() {
    this.svg.selectAll("*").remove()
    if (this.points.length < 2 || !this.width) return

    const x = scaleLinear().domain([0, this.points.at(-1).km]).range([PAD, this.width - PAD])
    const y = scaleLinear().domain(profileDomain(this.points)).range([HEIGHT - PAD, PAD])
    const peak = peakPoint(this.points)
    this.svg.attr("width", this.width).attr("height", HEIGHT)
    this.svg.append("path").datum(this.points).attr("fill", "none").attr("stroke", "var(--chart-accent)").attr("stroke-width", 1.5).attr("stroke-linejoin", "round")
      .attr("d", line().x(point => x(point.km)).y(point => y(point.alt)))
    this.svg.append("circle").attr("cx", x(peak.km)).attr("cy", y(peak.alt)).attr("r", 3).attr("fill", "var(--chart-highlight)").attr("pointer-events", "none")
    this.x = x
    this.y = y
    this.cursorLine = this.svg.append("line").attr("y1", 0).attr("y2", HEIGHT).attr("stroke", "var(--chart-highlight)").attr("stroke-width", 1.5).attr("pointer-events", "none").attr("display", "none")
    this.dot = this.svg.append("circle").attr("r", 3.5).attr("fill", "var(--chart-accent-highlight)").attr("display", "none").attr("pointer-events", "none")
    this.#showCursor()

    this.svg.append("rect").attr("width", this.width).attr("height", HEIGHT).attr("fill", "transparent")
      .on("mousemove", event => {
        const point = this.#nearest(x.invert(pointer(event)[0]))
        showTooltip(tooltipHtml(`${formatDistance(point.km)} km`, [["Elevation", `${Math.round(point.alt)} m`]]), event)
        publish(point.km * 1000)
      })
      .on("mouseleave", () => {
        hideTooltip()
        clear()
      })
  }

  #showCursor() {
    if (!this.cursorLine) return

    if (this.cursor == null) {
      this.cursorLine.attr("display", "none")
      this.dot.attr("display", "none")
    } else {
      const point = this.#nearest(this.cursor / 1000)
      this.cursorLine.attr("display", null).attr("x1", this.x(point.km)).attr("x2", this.x(point.km))
      this.dot.attr("display", null).attr("cx", this.x(point.km)).attr("cy", this.y(point.alt))
    }
  }

  #nearest(km) {
    const index = Math.min(this.points.length - 1, Math.max(0, BY_KM.center(this.points, km)))
    return this.points[index]
  }
}
