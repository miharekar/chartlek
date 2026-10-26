import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { bisector, quantile } from "d3-array"
import { brushX } from "d3-brush"
import { scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { formatDistance, formatDuration, formatPace } from "helpers/formatters"
import { paceScale } from "helpers/pace_scale"
import { observeSize } from "helpers/resize"
import { rangeStats } from "helpers/run_stats"
import { hideTooltip, moveTooltip, showTooltip } from "helpers/tooltip"

const MARGIN = { top: 8, right: 24, bottom: 24, left: 44 }

export default class extends Controller {
  static targets = ["chart", "stats", "unit"]
  static values = { bars: Array, splits: Array, unit: { type: String, default: "bars" } }

  connect() {
    this.svg = select(this.chartTarget).append("svg").attr("class", "block")
    this.stopObserving = observeSize(this.chartTarget, size => {
      this.size = size
      this.draw()
    })
  }

  disconnect() {
    this.stopObserving()
    this.svg.remove()
    hideTooltip()
  }

  unit(event) {
    this.unitValue = event.currentTarget.value
  }

  unitValueChanged() {
    this.unitTargets.forEach(button => button.setAttribute("aria-pressed", button.value === this.unitValue))
    if (this.size) this.draw()
  }

  draw() {
    const { width, height } = this.size
    const bars = this.unitValue === "splits" ? this.splitsValue : this.barsValue
    if (!bars.length) return

    let total = 0
    const starts = bars.map(bar => {
      const start = total
      total += bar.distance
      return start
    })
    const innerWidth = width - MARGIN.left - MARGIN.right
    const innerHeight = height - MARGIN.top - MARGIN.bottom
    const paces = bars.map(bar => bar.pace).sort((a, b) => a - b)
    const fastest = quantile(paces, 0.01) * 0.95
    const slowest = quantile(paces, 0.99) * 1.05
    const x = scaleLinear().domain([0, total / 1000]).range([0, innerWidth])
    const y = paceScale([fastest, slowest], [0, innerHeight])
    const top = pace => Math.min(innerHeight, Math.max(0, y(pace)))

    this.svg.attr("width", width).attr("height", height).selectAll("*").remove()
    const chart = this.svg.append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)

    const yAxis = chart.append("g").call(axisLeft(y).ticks(5).tickSize(-innerWidth))
    const xAxis = chart.append("g").attr("transform", `translate(0,${innerHeight})`).call(axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 80))).tickFormat(value => `${value} km`).tickSize(4))
    for (const axis of [xAxis, yAxis]) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }
    xAxis.selectAll("line").attr("stroke", "var(--chart-axis)")

    const rects = chart.append("g").selectAll("rect").data(bars).join("rect")
      .attr("x", (_, index) => x(starts[index] / 1000))
      .attr("width", bar => Math.max(1, x(bar.distance / 1000) - 1))
      .attr("y", bar => top(bar.pace))
      .attr("height", bar => innerHeight - top(bar.pace))
      .attr("fill", "var(--chart-accent)")

    const showAll = () => this.#renderStats(rangeStats(bars, 0, total), false)
    showAll()

    const brush = brushX().extent([[0, 0], [innerWidth, innerHeight]]).on("brush end", ({ selection }) => {
      if (!selection) {
        rects.attr("fill", "var(--chart-accent)")
        return showAll()
      }
      const [from, to] = selection.map(position => x.invert(position) * 1000)
      rects.attr("fill", (bar, index) => (starts[index] + bar.distance > from && starts[index] < to ? "var(--chart-accent-highlight)" : "var(--chart-accent)"))
      this.#renderStats(rangeStats(bars, from, to), true)
    })
    const layer = chart.append("g").call(brush)
    layer.select(".selection").attr("fill", "var(--chart-accent-low)").attr("fill-opacity", 0.3).attr("stroke", "var(--chart-accent-highlight)")

    const bySpan = bisector((start, position) => start - position)
    layer.on("mousemove", event => {
      const position = x.invert(pointer(event)[0]) * 1000
      const index = Math.max(0, bySpan.right(starts, position) - 1)
      showTooltip(this.#tooltipHtml(bars[index], starts[index]), event)
      moveTooltip(event)
    }).on("mouseleave", () => hideTooltip())
  }

  #renderStats(stats, brushed) {
    const parts = [`${formatDistance(stats.distance / 1000)} km`, formatDuration(stats.time)]
    if (stats.pace != null) parts.push(`${formatPace(stats.pace)} /km`)
    if (stats.hr != null) parts.push(`${Math.round(stats.hr)} bpm`)
    if (stats.cad != null) parts.push(`${Math.round(stats.cad)} spm`)
    this.statsTarget.textContent = `${brushed ? "Selection" : "Whole run"}: ${parts.join(" · ")}`
  }

  #tooltipHtml(bar, start) {
    const row = (label, value) => `<div class="text-zinc-500 dark:text-zinc-400">${label}</div><div class="text-right">${value}</div>`
    return `
      <div class="mb-1 text-zinc-500 dark:text-zinc-400">${formatDistance(start / 1000)}–${formatDistance((start + bar.distance) / 1000)} km</div>
      <div class="grid grid-cols-[auto_auto] gap-x-4">
        ${row("Pace", `${formatPace(bar.pace)} /km`)}
        ${bar.hr == null ? "" : row("HR", `${bar.hr} bpm`)}
        ${bar.cad == null ? "" : row("Cadence", `${bar.cad} spm`)}
      </div>`
  }
}
