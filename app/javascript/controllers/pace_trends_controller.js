import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { bisector, extent } from "d3-array"
import { Delaunay } from "d3-delaunay"
import { pointer, select } from "d3-selection"
import { scaleLinear, scaleUtc } from "d3-scale"
import { curveMonotoneX, line } from "d3-shape"
import { utcDay } from "d3-time"
import { formatDate, formatDistance, formatDuration, formatPace } from "helpers/formatters"
import { formatChange, formatFinishDelta } from "helpers/pace_trends_format"
import { activePreset, PRESETS, presetWindow } from "helpers/pace_trends_presets"
import { predictTime } from "helpers/predictions"
import { linearRegression, weeklyChange } from "helpers/regression"
import { observeSize } from "helpers/resize"
import { createTimeline } from "helpers/timeline"
import { parseTime } from "helpers/time"
import { hideTooltip, moveTooltip, showTooltip, tooltipHtml } from "helpers/tooltip"

const MARGIN = { top: 12, right: 16, bottom: 28, left: 44 }
const DAY_MS = 86400000
const HOVER_RADIUS = 16
const BY_TIME = bisector(run => run.t)

export default class extends Controller {
  static targets = ["chart", "timeline", "range", "change", "cut", "verb", "delta", "distance", "message", "link", "preset"]
  static values = { payload: Object }

  connect() {
    const { runs, tables, domain, window: selection } = this.payloadValue
    this.tables = Object.fromEntries(tables.map(({ label, table }) => [label, table]))
    this.domain = domain.map(parseTime)
    this.distance = this.payloadValue.distance
    this.runs = runs.map(run => ({ ...run, value: run.vdot }))
    this.muted = this.runs.filter(run => !run.top)
    this.top = this.runs.filter(run => run.top)
    this.x = scaleUtc()
    this.y = scaleLinear()
    this.#buildChart()

    this.timeline = createTimeline(this.timelineTarget, {
      data: this.runs.map(run => ({ date: parseTime(run.t), value: run.s / 3600 })),
      domain: domain.map(parseTime),
      selection: selection.map(parseTime),
      height: 88,
      onBrush: range => this.#setRange(range),
      onEnd: range => {
        this.#setRange(range)
        this.#syncUrl()
      }
    })
    this.range = this.timeline.selection().map(Number)
    this.disconnectSize = observeSize(this.chartTarget, ({ width }) => this.#resize(width))
  }

  disconnect() {
    this.disconnectSize?.()
    this.timeline?.destroy()
    this.svg?.remove()
    hideTooltip()
  }

  preset(event) {
    const { months } = PRESETS.find(({ key }) => key === event.currentTarget.dataset.preset)
    this.timeline.setSelection(presetWindow(months, this.domain))
    this.#setRange(this.timeline.selection())
    this.#syncUrl()
  }

  changeDistance() {
    this.distance = this.distanceTarget.value
    this.#renderHeader()
    this.#syncUrl()
  }

  #buildChart() {
    const values = extent(this.runs, run => run.value)
    const pad = (values[1] - values[0]) * 0.04
    this.y.domain([values[0] - pad, values[1] + pad]).nice()

    this.svg = select(this.chartTarget).append("svg").attr("class", "block w-full")
    this.clipId = `pace-trends-clip-${Math.random().toString(36).slice(2)}`
    this.clip = this.svg.append("defs").append("clipPath").attr("id", this.clipId).append("rect")
    this.xAxis = this.svg.append("g")
    this.yAxis = this.svg.append("g")
    this.axisLabel = this.svg.append("text").attr("fill", "var(--chart-axis)").attr("font-size", 11).attr("x", MARGIN.left).attr("y", 9).text("VDOT")
    this.plot = this.svg.append("g").attr("clip-path", `url(#${this.clipId})`)
    this.band = this.plot.append("path").attr("fill", "var(--chart-accent)").attr("fill-opacity", 0.14)
    this.trend = this.plot.append("path").attr("fill", "none").attr("stroke", "var(--chart-accent)").attr("stroke-width", 1.5)
    this.mutedDots = this.plot.append("path").attr("fill", "none").attr("stroke", "var(--chart-muted)").attr("stroke-opacity", 0.9).attr("stroke-width", 5).attr("stroke-linecap", "round")
    this.topLine = this.plot.append("path").attr("fill", "none").attr("stroke", "var(--chart-highlight)").attr("stroke-opacity", 0.4).attr("stroke-width", 1.5)
    this.topDots = this.plot.append("path").attr("fill", "none").attr("stroke", "var(--chart-highlight)").attr("stroke-width", 7).attr("stroke-linecap", "round")
    this.ring = this.svg.append("circle").attr("r", 7).attr("fill", "none").attr("stroke", "var(--chart-accent-highlight)").attr("stroke-width", 2).attr("pointer-events", "none").attr("display", "none")
    this.overlay = this.svg.append("rect").attr("fill", "transparent")
    this.overlay.on("mousemove", event => this.#hover(event)).on("mouseleave", () => this.#unhover()).on("click", event => this.#open(event))
  }

  #resize(width) {
    this.width = width
    this.height = Math.round(Math.min(420, Math.max(260, width * 0.36)))
    this.x.range([MARGIN.left, width - MARGIN.right])
    this.y.range([this.height - MARGIN.bottom, MARGIN.top])
    const plotWidth = width - MARGIN.left - MARGIN.right
    const plotHeight = this.height - MARGIN.top - MARGIN.bottom
    this.svg.attr("width", width).attr("height", this.height)
    this.clip.attr("x", MARGIN.left).attr("y", MARGIN.top).attr("width", plotWidth).attr("height", plotHeight)
    this.overlay.attr("x", MARGIN.left).attr("y", MARGIN.top).attr("width", plotWidth).attr("height", plotHeight)
    this.#render()
  }

  #setRange(range) {
    this.range = range.map(Number)
    this.#render()
  }

  #render() {
    if (!this.width) return
    const [start, end] = this.range
    this.x.domain([start, end])
    this.delaunay = null

    const muted = this.#within(this.muted)
    const top = this.#within(this.top)
    this.visible = this.#within(this.runs)
    this.#drawAxes()
    this.#drawDots(this.mutedDots, muted)
    this.#drawDots(this.topDots, top)
    const path = line().x(run => this.x(run.t)).y(run => this.y(run.value)).curve(curveMonotoneX)
    this.topLine.attr("d", top.length > 1 ? path(top) : null)

    this.fit = linearRegression(top.map(run => ({ x: run.t / DAY_MS, y: run.value })))
    this.#drawFit()
    this.#renderHeader()
  }

  #within(runs) {
    const [start, end] = this.range
    return runs.slice(BY_TIME.left(runs, start), BY_TIME.left(runs, end))
  }

  #drawAxes() {
    this.xAxis.attr("transform", `translate(0,${this.height - MARGIN.bottom})`).call(axisBottom(this.x).ticks(Math.max(2, Math.floor(this.width / 110))).tickSizeOuter(0))
    this.yAxis.attr("transform", `translate(${MARGIN.left},0)`).call(axisLeft(this.y).ticks(6).tickSize(-(this.width - MARGIN.left - MARGIN.right)).tickSizeOuter(0))
    for (const axis of [this.xAxis, this.yAxis]) {
      axis.select(".domain").attr("stroke", "var(--chart-grid)")
      axis.selectAll(".tick line").attr("stroke", "var(--chart-grid)")
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
    }
    this.yAxis.select(".domain").remove()
  }

  #drawDots(path, runs) {
    path.attr("d", runs.map(run => `M${this.x(run.t).toFixed(1)},${this.y(run.value).toFixed(1)}h0`).join(""))
  }

  #drawFit() {
    const [start, end] = this.range
    if (this.fit) {
      const { at, sd } = this.fit
      const [startDay, endDay] = [start / DAY_MS, end / DAY_MS]
      const [x0, x1] = [this.x(start), this.x(end)]
      const [y0, y1] = [this.y(at(startDay)), this.y(at(endDay))]
      const [d0, d1] = [this.y(at(startDay) - sd) - y0, this.y(at(endDay) - sd) - y1]
      this.band.attr("d", `M${x0},${y0 - d0}L${x1},${y1 - d1}L${x1},${y1 + d1}L${x0},${y0 + d0}Z`)
      this.trend.attr("d", `M${x0},${y0}L${x1},${y1}`)
    } else {
      this.band.attr("d", null)
      this.trend.attr("d", null)
    }
  }

  #renderHeader() {
    const active = activePreset(this.range, this.domain)
    this.presetTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.preset === active))
    const [start, end] = this.range
    this.rangeTarget.textContent = `${formatDate(start)} – ${formatDate(utcDay.offset(new Date(end), -1))}`
    this.messageTarget.hidden = Boolean(this.fit)
    this.changeTarget.hidden = !this.fit
    this.cutTarget.hidden = !this.fit
    if (!this.fit) return

    const perWeek = weeklyChange(this.fit.slope)
    this.changeTarget.innerHTML = `Change in VDOT: <strong>${formatChange(perWeek)}</strong>`
    const table = this.tables[this.distance]
    const seconds = predictTime(table, this.fit.at(start / DAY_MS)) - predictTime(table, this.fit.at(end / DAY_MS))
    const { verb, time } = formatFinishDelta(seconds)
    this.verbTarget.textContent = verb
    this.deltaTarget.textContent = time
  }

  #nearest(event) {
    if (!this.visible.length) return
    this.delaunay ||= Delaunay.from(this.visible, run => this.x(run.t), run => this.y(run.value))
    const [px, py] = pointer(event, this.svg.node())
    const run = this.visible[this.delaunay.find(px, py)]
    if (run && Math.hypot(this.x(run.t) - px, this.y(run.value) - py) <= HOVER_RADIUS) return run
  }

  #hover(event) {
    const run = this.#nearest(event)
    if (!run) return this.#unhover()

    this.overlay.style("cursor", "pointer")
    this.ring.attr("display", null).attr("cx", this.x(run.t)).attr("cy", this.y(run.value))
    showTooltip(this.#tooltipHtml(run), event)
    moveTooltip(event)
  }

  #unhover() {
    this.overlay.style("cursor", null)
    this.ring.attr("display", "none")
    hideTooltip()
  }

  #open(event) {
    const run = this.#nearest(event)
    if (run) window.Turbo.visit(run.url)
  }

  #tooltipHtml(run) {
    return tooltipHtml(formatDate(run.t), [
      ["VDOT", run.vdot.toFixed(1)],
      ["Distance", `${formatDistance(run.km)} km`],
      ["Pace", `${formatPace(run.s / run.km)} /km`],
      ["Time", formatDuration(run.s)]
    ], { heading: run.name || "Untitled run" })
  }

  #syncUrl() {
    const [start, end] = this.range
    const params = {
      from: new Date(start).toISOString().slice(0, 10),
      to: utcDay.offset(new Date(end), -1).toISOString().slice(0, 10),
      distance: this.distance
    }
    const url = new URL(location.href)
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value)
    history.replaceState(history.state, "", url)

    for (const link of this.linkTargets) {
      const href = new URL(link.href)
      for (const [key, value] of Object.entries(params)) href.searchParams.set(key, value)
      link.href = href.pathname + href.search
    }
  }
}
