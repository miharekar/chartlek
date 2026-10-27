import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { bisector, extent } from "d3-array"
import { scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { area, line } from "d3-shape"
import { formatDistance } from "helpers/formatters"
import { zoneBands } from "helpers/hr_zones"
import { observeSize } from "helpers/resize"
import { clear, publish, subscribe } from "helpers/run_cursor"

const MARGIN = { top: 20, right: 24, bottom: 4, left: 44 }
const AXIS_HEIGHT = 20
const CHART_HEIGHT = 180

const CHARTS = [
  { key: "alt", label: "Elevation", unit: "m", fill: true },
  { key: "hr", label: "Heart rate", unit: "bpm" },
  { key: "cad", label: "Cadence", unit: "spm" }
]

const BY_DISTANCE = bisector(distance => distance)

export default class extends Controller {
  static targets = ["chart"]
  static values = { series: Object, zones: Array }

  connect() {
    this.root = select(this.chartTarget).append("div")
    this.unsubscribe = subscribe(distance => {
      this.cursor = distance
      this.#show()
    })
    this.stopObserving = observeSize(this.chartTarget, ({ width }) => {
      this.width = width
      this.draw()
    })
  }

  disconnect() {
    this.stopObserving()
    this.unsubscribe()
    this.root.remove()
    clear()
  }

  draw() {
    const { d, ...rest } = this.seriesValue
    const distances = d.map(meters => meters / 1000)
    this.distances = distances
    const charts = CHARTS.filter(chart => rest[chart.key])
    const innerWidth = this.width - MARGIN.left - MARGIN.right
    const x = scaleLinear().domain([0, distances.at(-1)]).range([0, innerWidth])
    this.root.selectAll("*").remove()
    this.hovers = []

    charts.forEach((chart, index) => {
      const last = index === charts.length - 1
      this.#drawChart(chart, rest[chart.key], distances, x, innerWidth, last)
    })
    this.#show()
  }

  #drawChart({ key, label, unit, fill }, values, distances, x, innerWidth, last) {
    const innerHeight = CHART_HEIGHT - MARGIN.top - MARGIN.bottom
    const height = CHART_HEIGHT + (last ? AXIS_HEIGHT : 0)
    const [low, high] = extent(values)
    const pad = Math.max((high - low) * 0.1, 1)
    const y = scaleLinear().domain([low - pad, high + pad]).range([innerHeight, 0]).nice(3)

    const svg = this.root.append("svg").attr("class", "block").attr("width", this.width).attr("height", height)
    const chart = svg.append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)
    const defined = (_, index) => values[index] != null

    if (key === "hr") {
      const [bottom, top] = y.domain()
      for (const { zone, from, to } of zoneBands(this.zonesValue, bottom, top)) {
        chart.append("rect").attr("x", 0).attr("width", innerWidth).attr("y", y(to)).attr("height", y(from) - y(to)).attr("fill", `var(--hr-zone-${zone})`).attr("fill-opacity", 0.14).attr("pointer-events", "none")
      }
    }

    const yAxis = chart.append("g").call(axisLeft(y).ticks(3).tickSize(-innerWidth))
    yAxis.select(".domain").remove()
    yAxis.selectAll("text").attr("fill", "var(--chart-axis)")
    yAxis.selectAll("line").attr("stroke", "var(--chart-grid)")

    if (fill) {
      chart.append("path").datum(distances).attr("fill", "var(--chart-accent-low)").attr("fill-opacity", 0.5)
        .attr("d", area().defined(defined).x(distance => x(distance)).y0(innerHeight).y1((_, index) => y(values[index])))
    }
    chart.append("path").datum(distances).attr("fill", "none").attr("stroke", "var(--chart-accent)").attr("stroke-width", 1.5)
      .attr("d", line().defined(defined).x(distance => x(distance)).y((_, index) => y(values[index])))

    if (last) {
      const xAxis = svg.append("g").attr("transform", `translate(${MARGIN.left},${CHART_HEIGHT - MARGIN.bottom})`).call(axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 80))).tickFormat(value => `${value} km`).tickSize(4))
      xAxis.select(".domain").remove()
      xAxis.selectAll("text").attr("fill", "var(--chart-axis)")
      xAxis.selectAll("line").attr("stroke", "var(--chart-axis)")
    }

    svg.append("text").attr("x", MARGIN.left).attr("y", 12).attr("font-size", 11).attr("fill", "var(--chart-axis)").text(label)
    const readout = svg.append("text").attr("x", this.width - MARGIN.right).attr("y", 12).attr("text-anchor", "end").attr("font-size", 11).attr("fill", "var(--chart-axis)")
    const cursor = chart.append("line").attr("y1", 0).attr("y2", innerHeight).attr("stroke", "var(--chart-highlight)").attr("stroke-width", 1.5).attr("pointer-events", "none").attr("display", "none")
    this.hovers.push({ cursor, readout, unit, x, values })

    chart.append("rect").attr("width", innerWidth).attr("height", innerHeight).attr("fill", "transparent")
      .on("mousemove", event => publish(x.invert(pointer(event)[0]) * 1000))
      .on("mouseleave", () => clear())
  }

  #show() {
    if (!this.hovers) return
    if (this.cursor == null) return this.#unhover()

    const distances = this.distances
    const index = Math.min(distances.length - 1, Math.max(0, BY_DISTANCE.center(distances, this.cursor / 1000)))
    for (const { cursor, readout, unit, x, values } of this.hovers) {
      const value = values[index]
      cursor.attr("display", null).attr("x1", x(distances[index])).attr("x2", x(distances[index]))
      readout.text(`${value == null ? "–" : Math.round(value)} ${unit} · ${formatDistance(distances[index])} km`)
    }
  }

  #unhover() {
    for (const { cursor, readout } of this.hovers) {
      cursor.attr("display", "none")
      readout.text("")
    }
  }
}
