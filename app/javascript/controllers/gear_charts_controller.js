import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { max } from "d3-array"
import { scaleBand, scaleLinear, scaleUtc } from "d3-scale"
import { select } from "d3-selection"
import { line, stack } from "d3-shape"
import { utcFormat } from "d3-time-format"
import { formatDistance } from "helpers/formatters"
import { cumulative, initialHidden, monthRows, seriesColor, stackRows, toggled, zoom } from "helpers/gear_charts"
import { observeSize } from "helpers/resize"
import { scrub } from "helpers/scrub"
import { parseTime } from "helpers/time"
import { hideTooltip, moveTooltip, showTooltip, tooltipHtml } from "helpers/tooltip"

const MARGIN = { top: 8, right: 12, bottom: 24, left: 52 }
const monthYear = utcFormat("%b %Y")
const monthShort = utcFormat("%b %y")
const MAX_MONTH_TICKS = 18

export default class extends Controller {
  static targets = ["bars", "lines", "toggle"]
  static values = { data: Object }

  connect() {
    const { months, gears } = this.dataValue
    this.months = months.map(parseTime)
    this.gears = gears
    this.colors = new Map(gears.map((gear, index) => [gear.id, seriesColor(index)]))
    this.hidden = initialHidden(gears)
    this.sizes = {}
    this.svgs = {}
    this.stops = [["bars", () => this.#drawBars()], ["lines", () => this.#drawLines()]].map(([name, draw]) => {
      const target = this[`${name}Target`]
      this.svgs[name] = select(target).append("svg").attr("class", "block").attr("role", "img").attr("aria-label", target.dataset.label)
      return observeSize(target, size => {
        if (size.width - MARGIN.left - MARGIN.right <= 0) return

        this.sizes[name] = size
        draw()
      })
    })
    this.#syncToggles()
  }

  disconnect() {
    this.stops.forEach(stop => stop())
    Object.values(this.svgs).forEach(svg => svg.remove())
    hideTooltip()
  }

  toggle(event) {
    this.hidden = toggled(this.hidden, event.currentTarget.dataset.id)
    this.#syncToggles()
    if (this.sizes.bars) this.#drawBars()
    if (this.sizes.lines) this.#drawLines()
  }

  get visible() {
    return this.gears.filter(gear => !this.hidden.has(gear.id))
  }

  #syncToggles() {
    this.toggleTargets.forEach(button => {
      button.setAttribute("aria-pressed", !this.hidden.has(button.dataset.id))
      button.querySelector("[data-swatch]").style.background = this.colors.get(button.dataset.id)
    })
  }

  #frame(name, yMax) {
    const { width, height } = this.sizes[name]
    const innerWidth = width - MARGIN.left - MARGIN.right
    const innerHeight = height - MARGIN.top - MARGIN.bottom
    const y = scaleLinear().domain([0, yMax || 1]).nice().range([innerHeight, 0])

    this.svgs[name].attr("width", width).attr("height", height).selectAll("*").remove()
    const chart = this.svgs[name].append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)
    const yAxis = chart.append("g").call(axisLeft(y).ticks(5).tickSize(-innerWidth).tickFormat(value => `${value} km`))
    return { chart, y, innerWidth, innerHeight, yAxis }
  }

  #style(...axes) {
    for (const axis of axes) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }
  }

  #xTicks(months) {
    const indexes = months.map((_, index) => index)
    return months.length <= MAX_MONTH_TICKS ? indexes : indexes.filter(index => months[index].getUTCMonth() === 0 || index === 0)
  }

  #drawBars() {
    const { months, gears: visible } = zoom(this.months, this.visible)
    const rows = stackRows(months, visible)
    const stacked = stack().keys(visible.map(gear => gear.id)).value((row, key) => row[key])(rows)
    const { chart, y, innerWidth, innerHeight, yAxis } = this.#frame("bars", max(stacked.at(-1) || [], row => row[1]))
    const indexes = months.map((_, index) => index)
    const x = scaleBand().domain(indexes).range([0, innerWidth]).padding(0.15)
    const xAxis = chart.append("g").attr("transform", `translate(0,${innerHeight})`).call(
      axisBottom(x).tickValues(this.#xTicks(months).filter((_, position, all) => all.length <= Math.ceil(innerWidth / 48) || position % Math.ceil(all.length / Math.ceil(innerWidth / 48)) === 0)).tickFormat(index => (months.length <= MAX_MONTH_TICKS ? monthShort(months[index]) : months[index].getUTCFullYear())).tickSize(4)
    )
    this.#style(xAxis, yAxis)
    xAxis.selectAll("line").attr("stroke", "var(--chart-axis)")

    chart.append("g").selectAll("g").data(stacked).join("g").attr("fill", series => this.colors.get(series.key)).selectAll("rect").data(series => series).join("rect")
      .attr("x", (_, index) => x(index))
      .attr("width", x.bandwidth())
      .attr("y", row => y(row[1]))
      .attr("height", row => Math.max(0, y(row[0]) - y(row[1])))
      .attr("class", "pointer-events-none")

    this.#hitAreas(chart, indexes, index => x(index) - x.step() * 0.075, x.step(), innerHeight, visible, (gear, index) => gear.km[index], months)
  }

  #drawLines() {
    const { months, gears: visible } = zoom(this.months, this.visible, 1)
    const series = visible.map(gear => ({ gear, totals: cumulative(gear.km) }))
    const { chart, y, innerWidth, innerHeight, yAxis } = this.#frame("lines", max(series, entry => max(entry.totals, value => value)))
    const x = scaleUtc().domain([months[0], months.at(-1)]).range([0, innerWidth])
    const indexes = months.map((_, index) => index)
    const xAxis = chart.append("g").attr("transform", `translate(0,${innerHeight})`).call(axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 80))).tickSizeOuter(0))
    this.#style(xAxis, yAxis)

    const path = line().defined(value => value != null).x((_, index) => x(months[index])).y(value => y(value ?? 0))
    chart.append("g").selectAll("path").data(series).join("path")
      .attr("fill", "none")
      .attr("stroke", entry => this.colors.get(entry.gear.id))
      .attr("stroke-width", 1.75)
      .attr("stroke-linejoin", "round")
      .attr("d", entry => path(entry.totals))
    this.lineTotals = new Map(series.map(entry => [entry.gear.id, entry.totals]))

    const step = months.length > 1 ? innerWidth / (months.length - 1) : innerWidth
    this.#hitAreas(chart, indexes, index => x(months[index]) - step / 2, step, innerHeight, visible, (gear, index) => this.lineTotals.get(gear.id)[index], months, true)
  }

  #hitAreas(chart, indexes, left, step, innerHeight, visible, value, months, running = false) {
    const hits = chart.append("g").selectAll("rect").data(indexes).join("rect")
      .attr("x", left)
      .attr("width", step)
      .attr("height", innerHeight + MARGIN.bottom)
      .attr("fill", "transparent")
    scrub(hits, {
      mode: "items",
      enter: (event, index) => showTooltip(this.#tooltip(index, visible, value, months, running), event),
      move: event => moveTooltip(event),
      leave: () => hideTooltip()
    })
  }

  #tooltip(index, visible, value, months, running) {
    const rows = running ? visible.map(gear => [gear, value(gear, index)]).filter(([, km]) => km > 0) : monthRows(visible, index)
    const lines = rows.map(([gear, km]) => [gear.name, `${formatDistance(km)} km`])
    if (!running && rows.length > 1) lines.push(["Total", `${formatDistance(rows.reduce((sum, [, km]) => sum + km, 0))} km`])
    return tooltipHtml(monthYear(months[index]), lines.length ? lines : [["Runs", "none with gear"]])
  }
}
