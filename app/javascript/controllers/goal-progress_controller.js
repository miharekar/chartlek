import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { scaleLinear, scaleUtc } from "d3-scale"
import { pointer, select } from "d3-selection"
import { line } from "d3-shape"
import { formatDate, formatDistance } from "helpers/formatters"
import { catchUpLine, catchUpOpacity, DAY, dayIndexAt, hoverAt, pathAt, yMax } from "helpers/goal_progress"
import { observeSize } from "helpers/resize"
import { noMouseFocus, rovingTarget } from "helpers/roving"
import { scrub } from "helpers/scrub"
import { hideTooltip, showTooltip, showTooltipFor, tooltipHtml } from "helpers/tooltip"

const MARGIN = { top: 8, right: 12, bottom: 24, left: 52 }
const BAR_SHARE = 0.2

export default class extends Controller {
  static values = { data: Object }

  connect() {
    this.series = this.dataValue
    this.dailyAt = new Map(this.series.daily.map(day => [day.index, day]))
    this.index = null
    this.svg = select(this.element).append("svg").attr("class", "block").attr("role", "img").attr("aria-label", this.element.dataset.label)
    this.stop = observeSize(this.element, size => this.#draw(size))
  }

  disconnect() {
    this.stop()
    this.svg.remove()
    hideTooltip()
  }

  #draw({ width, height }) {
    const { start, days, goal_km: goalKm, cumulative, daily } = this.series
    const innerWidth = Math.max(0, width - MARGIN.left - MARGIN.right)
    const innerHeight = Math.max(0, height - MARGIN.top - MARGIN.bottom)
    const x = scaleUtc().domain([start, start + (days - 1) * DAY]).range([0, innerWidth])
    const y = scaleLinear().domain([0, yMax(this.series)]).nice().range([innerHeight, 0])
    const at = index => x(start + index * DAY)
    const path = line().x(([index]) => at(index)).y(([, km]) => y(km))
    this.at = at
    this.y = y
    this.innerHeight = innerHeight

    this.svg.attr("width", width).attr("height", height).selectAll("*").remove()
    const chart = this.svg.append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)
    const yAxis = chart.append("g").call(axisLeft(y).ticks(5).tickSize(-innerWidth).tickFormat(value => `${value} km`))
    const xAxis = chart.append("g").attr("transform", `translate(0,${innerHeight})`).call(axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 90))).tickSizeOuter(0))
    for (const axis of [xAxis, yAxis]) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }

    const biggest = Math.max(...daily.map(day => day.km), 1)
    const barWidth = Math.max(1.5, Math.min(10, (innerWidth / days) * 0.7))
    this.bars = chart.append("g").selectAll("rect").data(daily).join("rect")
      .attr("x", day => at(day.index) - barWidth / 2)
      .attr("width", barWidth)
      .attr("y", day => innerHeight - (day.km / biggest) * innerHeight * BAR_SHARE)
      .attr("height", day => (day.km / biggest) * innerHeight * BAR_SHARE)
      .attr("class", "pointer-events-none")

    chart.append("path").attr("d", path([[0, pathAt(goalKm, days, 0)], [days - 1, goalKm]])).attr("fill", "none").attr("stroke", "var(--chart-muted)").attr("stroke-width", 1.75).attr("stroke-dasharray", "2 4").attr("stroke-linecap", "round")

    const catchUp = catchUpLine(this.series)
    if (catchUp) {
      chart.append("path").attr("d", path(catchUp)).attr("fill", "none").attr("stroke", "var(--chart-behind)").attr("stroke-width", 2).attr("stroke-dasharray", "6 4").attr("stroke-opacity", catchUpOpacity(this.series.catch_up.ratio))
    }

    if (cumulative.length) {
      chart.append("path").attr("d", path(cumulative.map((km, index) => [index, km]))).attr("fill", "none").attr("stroke", "var(--chart-accent)").attr("stroke-width", 2).attr("stroke-linejoin", "round")
      chart.append("circle").attr("cx", at(cumulative.length - 1)).attr("cy", y(cumulative.at(-1))).attr("r", 4).attr("fill", "var(--chart-highlight)")
    }

    this.cursorLine = chart.append("line").attr("y1", 0).attr("y2", innerHeight).attr("stroke", "var(--chart-highlight)").attr("stroke-width", 1.5).attr("pointer-events", "none").attr("display", "none")
    this.cursorDot = chart.append("circle").attr("r", 4.5).attr("stroke", "var(--chart-highlight)").attr("stroke-width", 2).attr("pointer-events", "none").attr("display", "none")
    this.overlay = chart.append("rect").attr("width", innerWidth).attr("height", innerHeight).attr("fill", "transparent").attr("tabindex", 0).attr("role", "img")
      .attr("aria-label", `${this.element.dataset.label}. Left and right arrows step through days, Enter opens the run, Escape clears.`)
      .on("mousedown", noMouseFocus)
      .call(scrub, { move: event => this.#hover(event, x), leave: () => this.#leave() })
      .on("click", event => this.#open(this.#indexAt(event, x)))
      .on("blur", () => this.#leave())
      .on("keydown", event => this.#key(event))
    this.#showCursor()
  }

  #hover(event, x) {
    this.#select(this.#indexAt(event, x), html => showTooltip(html, event))
  }

  #indexAt(event, x) {
    return dayIndexAt(x.invert(pointer(event, this.overlay.node())[0]).getTime(), this.series.start, this.series.days)
  }

  #key(event) {
    if (event.key === "Escape") return this.#leave()
    if (event.key === "Enter") return this.#open(this.index)
    const last = this.series.days - 1
    const current = this.index ?? Math.max(0, this.series.cumulative.length - 1)
    const target = rovingTarget(event.key, current, last)
    if (target == null) return
    event.preventDefault()
    this.#select(target, html => showTooltipFor(html, this.cursorDot.node()))
  }

  #select(index, show) {
    this.index = index
    this.#showCursor()
    show(this.#tooltip(index))
  }

  #leave() {
    this.index = null
    this.#showCursor()
    hideTooltip()
  }

  #open(index) {
    const day = this.dailyAt.get(index)
    if (day) window.Turbo.visit(day.url)
  }

  #showCursor() {
    if (!this.cursorLine) return
    const index = this.index
    this.bars.attr("fill", day => (day.index === index ? "var(--chart-accent-highlight)" : "var(--chart-accent-low)"))
    this.overlay.style("cursor", this.dailyAt.has(index) ? "pointer" : null)
    if (index == null) {
      this.cursorLine.attr("display", "none")
      this.cursorDot.attr("display", "none")
      return
    }
    const { goal_km: goalKm, days } = this.series
    const hover = hoverAt(this.series, index)
    this.cursorLine.attr("x1", this.at(index)).attr("x2", this.at(index)).attr("display", null)
    this.cursorDot.attr("cx", this.at(index)).attr("cy", this.y(hover.past ? hover.done : pathAt(goalKm, days, index))).attr("fill", hover.past ? "var(--chart-accent)" : "var(--chart-muted)").attr("display", null)
  }

  #tooltip(index) {
    const hover = hoverAt(this.series, index)
    const day = this.dailyAt.get(index)
    const date = new Date(this.series.start + index * DAY)
    const rows = []

    if (hover.past) {
      rows.push(["Distance", `${formatDistance(hover.done)} km`], ["Direct path", `${formatDistance(hover.path)} km`], [hover.delta < 0 ? "Behind" : "Ahead", `${formatDistance(Math.abs(hover.delta))} km`])
      if (day) rows.push(["That day", `${formatDistance(day.km)} km${day.runs > 1 ? ` in ${day.runs} runs` : ""}`])
      if (this.series.ended && index === this.series.days - 1) rows.push(["Finished", `${formatDistance(hover.done)} of ${formatDistance(this.series.goal_km)} km`])
    } else {
      rows.push(["Direct path", `${formatDistance(hover.path)} km`])
    }
    if (hover.required != null) rows.push([hover.past ? "Needed per day from now" : "Needed per day from here", hover.remaining > 0 ? `${formatDistance(hover.required)} km` : "goal reached"])
    if (!hover.past && hover.remaining > 0) rows.push(["Left to run", `${formatDistance(hover.remaining)} km`])

    return tooltipHtml(formatDate(date), rows)
  }
}
