import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { extent, max } from "d3-array"
import { Delaunay } from "d3-delaunay"
import { scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { formatDate, formatDistance, formatPace } from "helpers/formatters"
import { paceScale } from "helpers/pace_scale"
import { observeSize } from "helpers/resize"
import { escapeHtml, hideTooltip, moveTooltip, showTooltip } from "helpers/tooltip"

const MARGIN = { top: 8, right: 12, bottom: 24, left: 44 }
const PACE_TICKS = [180, 240, 300, 360, 450, 600, 900, 1800]
const HIT_RADIUS = 14

const METRICS = {
  pace: { value: run => run.pace },
  hr: { value: run => run.hr },
  spi: { value: run => run.spi }
}

export default class extends Controller {
  static targets = ["chart"]
  static values = { data: Object, metric: { type: String, default: "pace" } }

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

  metric(event) {
    this.metricValue = event.target.value
  }

  metricValueChanged() {
    if (this.size) this.draw()
  }

  draw() {
    const { width, height } = this.size
    const { runs, last, average } = this.dataValue
    const key = this.metricValue
    const value = METRICS[key].value
    const innerWidth = width - MARGIN.left - MARGIN.right
    const innerHeight = height - MARGIN.top - MARGIN.bottom
    const shown = runs.map((run, index) => ({ run, index })).filter(({ run }) => value(run) != null)
    const x = scaleLinear()
      .domain([0, max(runs, run => run.km) || 1])
      .nice()
      .range([0, innerWidth])
    const y = this.yScale(key, shown.map(({ run }) => value(run)), innerHeight)
    const position = run => [x(run.km), Math.max(0, Math.min(innerHeight, y(value(run))))]

    this.svg.attr("width", width).attr("height", height).selectAll("*").remove()
    const chart = this.svg.append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)

    const yAxis = chart.append("g").call(this.yAxis(key, y).tickSize(-innerWidth))
    const xAxis = chart
      .append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 60))).tickSizeOuter(0))
    for (const axis of [xAxis, yAxis]) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }

    const points = shown.map(({ run }) => position(run))
    chart
      .append("g")
      .selectAll("circle")
      .data(points)
      .join("circle")
      .attr("cx", point => point[0])
      .attr("cy", point => point[1])
      .attr("r", 2.5)
      .attr("fill", "var(--chart-accent)")
      .attr("fill-opacity", 0.5)

    const lastRun = runs[last]
    if (value(lastRun) != null) {
      const [lastX, lastY] = position(lastRun)
      chart.append("circle").attr("cx", lastX).attr("cy", lastY).attr("r", 5).attr("fill", "var(--chart-highlight)").attr("stroke", "var(--chart-grid)")
    }
    if (average[key] != null) {
      chart
        .append("circle")
        .attr("cx", x(average.km))
        .attr("cy", y(average[key]))
        .attr("r", 7)
        .attr("fill", "none")
        .attr("stroke", "var(--chart-accent-highlight)")
        .attr("stroke-width", 2)
    }

    this.addHover(chart, shown, points, innerWidth, innerHeight)
  }

  yScale(key, values, innerHeight) {
    if (key === "pace") {
      const [fastest, slowest] = extent(values)
      const top = Math.max(150, fastest - 15)
      return paceScale([top, Math.max(Math.min(1800, slowest), top + 120)], [0, innerHeight])
    }
    const [low, high] = extent(values)
    return scaleLinear()
      .domain([low ?? 0, high ?? 1])
      .nice()
      .range([innerHeight, 0])
  }

  yAxis(key, y) {
    if (key === "pace") {
      const [fastest, slowest] = y.domain()
      return axisLeft(y).tickValues(PACE_TICKS.filter(pace => pace >= fastest && pace <= slowest))
    }
    return axisLeft(y).ticks(5)
  }

  addHover(chart, shown, points, innerWidth, innerHeight) {
    const delaunay = Delaunay.from(points)
    const ring = chart.append("circle").attr("r", 6).attr("fill", "none").attr("stroke", "var(--chart-axis)").attr("stroke-width", 1.5).attr("display", "none").attr("pointer-events", "none")
    let current

    chart
      .append("rect")
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .on("mousemove", event => {
        const [mouseX, mouseY] = pointer(event)
        const found = points.length ? delaunay.find(mouseX, mouseY) : -1
        const near = found >= 0 && Math.hypot(points[found][0] - mouseX, points[found][1] - mouseY) <= HIT_RADIUS
        current = near ? shown[found].run : null
        event.currentTarget.style.cursor = near ? "pointer" : "default"

        if (near) {
          ring.attr("display", null).attr("cx", points[found][0]).attr("cy", points[found][1])
          showTooltip(this.tooltip(current), event)
        } else {
          ring.attr("display", "none")
          hideTooltip()
        }
      })
      .on("mouseleave", () => {
        ring.attr("display", "none")
        hideTooltip()
      })
      .on("click", () => {
        if (current) window.open(current.href, "_blank", "noopener")
      })
  }

  tooltip(run) {
    const hr = run.hr == null ? "–" : `${run.hr} bpm`
    const spi = run.spi == null ? "–" : Math.round(run.spi)
    return `<div class="font-medium">${formatDate(run.t)}</div><div>${escapeHtml(run.name || "Run")}</div><div>${formatDistance(run.km)} km · ${formatPace(run.pace)} /km</div><div class="text-zinc-500">HR ${hr} · SPI ${spi}</div>`
  }
}
