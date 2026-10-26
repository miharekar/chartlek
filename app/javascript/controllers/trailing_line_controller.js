import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { bisector, max } from "d3-array"
import { scaleLinear, scaleUtc } from "d3-scale"
import { pointer, select } from "d3-selection"
import { area, line } from "d3-shape"
import { formatDate, formatDistance } from "helpers/formatters"
import { observeSize } from "helpers/resize"
import { parseTime } from "helpers/time"
import { clearSelection, getTimes, publish, spanSelection } from "helpers/linked_selection"
import { hideTooltip, moveTooltip, showTooltip } from "helpers/tooltip"

const MARGIN = { top: 8, right: 12, bottom: 24, left: 44 }
const DAY_MS = 86400000

export default class extends Controller {
  static targets = ["chart"]
  static values = { data: Object }

  connect() {
    this.points = this.dataValue.points.map(([date, km]) => ({ date: parseTime(date), km }))
    this.svg = select(this.chartTarget).append("svg").attr("class", "block")
    this.stopObserving = observeSize(this.chartTarget, size => this.draw(size))
  }

  disconnect() {
    this.stopObserving()
    this.svg.remove()
    hideTooltip()
    clearSelection()
  }

  draw({ width, height }) {
    const points = this.points
    const innerWidth = width - MARGIN.left - MARGIN.right
    const innerHeight = height - MARGIN.top - MARGIN.bottom
    const x = scaleUtc()
      .domain([points[0].date, points.at(-1).date])
      .range([0, innerWidth])
    const y = scaleLinear()
      .domain([0, max(points, point => point.km) || 1])
      .nice()
      .range([innerHeight, 0])

    this.svg.attr("width", width).attr("height", height).selectAll("*").remove()
    const chart = this.svg.append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)

    const yAxis = chart.append("g").call(axisLeft(y).ticks(5).tickSize(-innerWidth))
    const xAxis = chart
      .append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 80))).tickSizeOuter(0))
    for (const axis of [xAxis, yAxis]) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }

    chart
      .append("path")
      .datum(points)
      .attr("fill", "var(--chart-accent-low)")
      .attr("fill-opacity", 0.5)
      .attr("d", area().x(point => x(point.date)).y0(innerHeight).y1(point => y(point.km)))
    chart
      .append("path")
      .datum(points)
      .attr("fill", "none")
      .attr("stroke", "var(--chart-accent)")
      .attr("stroke-width", 1.75)
      .attr("stroke-linejoin", "round")
      .attr("d", line().x(point => x(point.date)).y(point => y(point.km)))
    if (points.length === 1) chart.append("circle").attr("cx", x(points[0].date)).attr("cy", y(points[0].km)).attr("r", 4).attr("fill", "var(--chart-accent)")

    const marker = chart.append("circle").attr("r", 4).attr("fill", "var(--chart-accent-highlight)").attr("display", "none").attr("pointer-events", "none")
    const bisect = bisector(point => point.date).center
    chart
      .append("rect")
      .attr("x", -MARGIN.left)
      .attr("width", width)
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .on("mousemove", event => {
        const point = points[bisect(points, x.invert(pointer(event)[0]))]
        marker.attr("display", null).attr("cx", x(point.date)).attr("cy", y(point.km))
        showTooltip(`<div class="font-medium">${formatDate(point.date)}</div><div>${formatDistance(point.km)} km in ${this.dataValue.days} days</div>`, event)
        const end = point.date.getTime() + DAY_MS
        publish(spanSelection(getTimes(), end - this.dataValue.days * DAY_MS, end, "trailing"))
      })
      .on("mouseleave", () => {
        marker.attr("display", "none")
        hideTooltip()
        clearSelection()
      })
  }
}
