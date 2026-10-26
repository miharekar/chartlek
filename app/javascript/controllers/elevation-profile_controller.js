import { Controller } from "@hotwired/stimulus"
import { bisector } from "d3-array"
import { scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { line } from "d3-shape"
import { formatDistance } from "helpers/formatters"
import { peakPoint, profileDomain, profilePoints } from "helpers/elevation_profile"
import { observeSize } from "helpers/resize"
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
    this.stopObserving = observeSize(this.chartTarget, ({ width }) => {
      this.width = width
      this.draw()
    })
  }

  disconnect() {
    this.stopObserving()
    hideTooltip()
    this.svg.remove()
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
    const dot = this.svg.append("circle").attr("r", 3.5).attr("fill", "var(--chart-accent-highlight)").attr("display", "none").attr("pointer-events", "none")

    this.svg.append("rect").attr("width", this.width).attr("height", HEIGHT).attr("fill", "transparent")
      .on("mousemove", event => {
        const point = this.#nearest(x.invert(pointer(event)[0]))
        dot.attr("display", null).attr("cx", x(point.km)).attr("cy", y(point.alt))
        showTooltip(tooltipHtml(`${formatDistance(point.km)} km`, [["Elevation", `${Math.round(point.alt)} m`]]), event)
      })
      .on("mouseleave", () => {
        dot.attr("display", "none")
        hideTooltip()
      })
  }

  #nearest(km) {
    const index = Math.min(this.points.length - 1, Math.max(0, BY_KM.center(this.points, km)))
    return this.points[index]
  }
}
