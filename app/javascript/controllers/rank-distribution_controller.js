import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { scaleLinear } from "d3-scale"
import { select } from "d3-selection"
import { formatDistance, formatPace } from "helpers/formatters"
import { distribution } from "helpers/rank_distribution"
import { observeSize } from "helpers/resize"
import { escapeHtml, hideTooltip, isTooltipFor, moveTooltip, showTooltipFor } from "helpers/tooltip"

const HEIGHT = 150
const MARGIN = { top: 18, right: 8, bottom: 24, left: 30 }

export default class extends Controller {
  static targets = ["chart"]
  static values = { values: Array, current: Number, metric: String }

  connect() {
    this.svg = select(this.chartTarget).append("svg").attr("class", "block").attr("role", "group")
    this.stopObserving = observeSize(this.chartTarget, ({ width }) => this.draw(width))
  }

  disconnect() {
    this.stopObserving()
    if (this.svg.selectAll("rect").nodes().some(isTooltipFor)) hideTooltip()
    this.svg.remove()
  }

  draw(width) {
    const bins = distribution(this.valuesValue, this.currentValue)
    this.svg.selectAll("*").remove()
    if (!bins.length) return
    const bottom = HEIGHT - MARGIN.bottom
    const x = scaleLinear().domain([bins[0].from, bins.at(-1).to]).range([MARGIN.left, width - MARGIN.right])
    const y = scaleLinear().domain([0, Math.max(...bins.map(bin => bin.count))]).nice(3).range([bottom, MARGIN.top])
    this.svg.attr("width", width).attr("height", HEIGHT)
    const axes = [
      this.svg.append("g").attr("transform", `translate(0,${bottom})`).call(axisBottom(x).ticks(Math.max(2, Math.floor(width / 65))).tickFormat(value => this.format(value)).tickSizeOuter(0)),
      this.svg.append("g").attr("transform", `translate(${MARGIN.left},0)`).call(axisLeft(y).ticks(3).tickFormat(value => Number.isInteger(value) ? value : "").tickSizeOuter(0))
    ]
    for (const axis of axes) {
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line, path").attr("stroke", "var(--chart-grid)")
    }
    this.svg.append("text").attr("x", MARGIN.left).attr("y", 11).attr("font-size", 10).attr("fill", "var(--chart-axis)").text("Runs")
    this.svg.selectAll("rect").data(bins).join("rect")
      .attr("tabindex", 0).attr("role", "img").attr("aria-label", bin => this.summary(bin).join(". "))
      .attr("x", bin => x(bin.from)).attr("width", bin => Math.max(1, x(bin.to) - x(bin.from) - 1))
      .attr("y", bin => y(bin.count)).attr("height", bin => bottom - y(bin.count))
      .attr("fill", bin => bin.current ? "var(--chart-highlight)" : "var(--chart-accent)")
      .on("mouseenter", (event, bin) => {
        showTooltipFor(this.tooltip(bin), event.currentTarget)
        if (document.activeElement !== event.currentTarget) moveTooltip(event)
      })
      .on("mousemove", event => {
        if (isTooltipFor(event.currentTarget) && document.activeElement !== event.currentTarget) moveTooltip(event)
      })
      .on("mouseleave", event => {
        if (isTooltipFor(event.currentTarget) && document.activeElement !== event.currentTarget) hideTooltip()
      })
      .on("focus", (event, bin) => {
        select(event.currentTarget).attr("stroke", "var(--chart-axis)").attr("stroke-width", 2)
        showTooltipFor(this.tooltip(bin), event.currentTarget)
      })
      .on("blur", event => {
        select(event.currentTarget).attr("stroke", null)
        if (isTooltipFor(event.currentTarget)) hideTooltip()
      })
      .on("keydown", event => {
        if (event.key === "Escape" && isTooltipFor(event.currentTarget)) hideTooltip()
      })
    this.svg.append("line").attr("x1", x(this.currentValue)).attr("x2", x(this.currentValue)).attr("y1", MARGIN.top).attr("y2", bottom)
      .attr("stroke", "var(--chart-highlight)").attr("stroke-width", 2).attr("pointer-events", "none")
    this.svg.append("circle").attr("cx", x(this.currentValue)).attr("cy", MARGIN.top).attr("r", 3).attr("fill", "var(--chart-highlight)").attr("pointer-events", "none")
  }

  format(value) {
    return this.metricValue === "pace" ? formatPace(value) : formatDistance(value)
  }

  tooltip(bin) {
    return this.summary(bin).map(text => `<div>${escapeHtml(text)}</div>`).join("")
  }

  summary(bin) {
    const unit = this.metricValue === "pace" ? "min/km" : "km"
    const range = `${this.format(bin.from)}–${this.format(bin.to)} ${unit}`
    const lines = [range, `${bin.count} ${bin.count === 1 ? "run" : "runs"}`]
    if (bin.current) lines.push(`This run: ${this.format(this.currentValue)} ${unit}`)
    return lines
  }
}
