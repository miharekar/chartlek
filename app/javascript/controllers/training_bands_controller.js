import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { range } from "d3-array"
import { pointer, select } from "d3-selection"
import { scaleLinear, scaleUtc } from "d3-scale"
import { area } from "d3-shape"
import { utcDay } from "d3-time"
import { formatDate, formatDuration } from "helpers/formatters"
import { activePreset, PRESETS, presetWindow } from "helpers/pace_trends_presets"
import { observeSize } from "helpers/resize"
import { noMouseFocus } from "helpers/roving"
import { createTimeline } from "helpers/timeline"
import { parseTime } from "helpers/time"
import { hideTooltip, showTooltip, showTooltipFor, tooltipHtml } from "helpers/tooltip"
import { groupRows, peak, stackBands, visibleBands, WEEK_MS, weekIndex, weekTotals } from "helpers/training_bands"

const MARGIN = { top: 18, right: 16, bottom: 22, left: 44 }
const HEIGHT = 360
const DAY_MS = 86400000

export default class extends Controller {
  static targets = ["chart", "timeline", "range", "preset", "category", "view", "filters"]
  static values = { payload: Object }

  connect() {
    this.payload = this.payloadValue
    this.start = this.payload.start
    this.weeks = this.payload.weeks
    this.categories = this.payload.categories
    this.totals = Object.fromEntries(Object.entries(this.categories).map(([name, category]) => [name, weekTotals(category, this.weeks)]))
    this.hidden = Object.fromEntries(Object.keys(this.categories).map(name => [name, new Set()]))
    this.category = this.payload.category
    this.view = this.payload.view
    this.domain = this.payload.domain.map(parseTime)
    this.x = scaleUtc()
    this.y = scaleLinear()
    this.week = null

    this.#build()
    this.#restack()

    this.timeline = createTimeline(this.timelineTarget, {
      data: this.#timelineData(),
      domain: this.domain,
      selection: this.payload.window.map(parseTime),
      height: 72,
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

  changeCategory(event) {
    this.category = event.currentTarget.dataset.value
    this.#restack()
    this.#render()
    this.#syncUrl()
  }

  changeView(event) {
    this.view = event.currentTarget.dataset.value
    this.#restack()
    this.#render()
    this.#syncUrl()
  }

  toggle(event) {
    const button = event.currentTarget
    const group = Number(button.dataset.group)
    const hidden = this.hidden[this.category]
    if (hidden.has(group)) hidden.delete(group)
    else hidden.add(group)
    button.setAttribute("aria-pressed", !hidden.has(group))
    this.#restack()
    this.#render()
  }

  #timelineData() {
    const [first, last] = this.domain
    const totals = Object.values(this.totals)[0]
    return totals.flatMap((seconds, week) => range(7).map(day => ({ date: new Date(this.start + week * WEEK_MS + day * DAY_MS), value: seconds / 3600 / 7 }))).filter(({ date }) => date >= first && date <= last)
  }

  #build() {
    this.svg = select(this.chartTarget).append("svg").attr("class", "block w-full").attr("height", HEIGHT)
    this.clipId = `training-bands-clip-${Math.random().toString(36).slice(2)}`
    this.clip = this.svg.append("defs").append("clipPath").attr("id", this.clipId).append("rect")
    this.yAxis = this.svg.append("g")
    this.xAxis = this.svg.append("g")
    this.unit = this.svg.append("text").attr("fill", "var(--chart-axis)").attr("font-size", 11).attr("x", MARGIN.left).attr("y", 10)
    this.plot = this.svg.append("g").attr("clip-path", `url(#${this.clipId})`)
    this.cursorLine = this.svg.append("line").attr("stroke", "var(--chart-highlight)").attr("stroke-width", 1.5).attr("pointer-events", "none").attr("display", "none")
    this.overlay = this.svg.append("rect").attr("fill", "transparent").attr("tabindex", 0).attr("role", "img").attr("aria-label", `${this.chartTarget.dataset.label}. Left and right arrows step through weeks, Escape clears.`)
      .on("mousedown", noMouseFocus)
      .on("mousemove", event => this.#hover(event))
      .on("mouseleave", () => this.#leave())
      .on("blur", () => this.#leave())
      .on("keydown", event => this.#key(event))
  }

  #restack() {
    const category = this.categories[this.category]
    const stack = stackBands(category, visibleBands(category, this.hidden[this.category]), this.totals[this.category], this.view === "percent")
    this.top = stack.top
    this.layers = stack.layers.map(layer => ({
      ...layer,
      generate: area().x(this.#weekX).y0(index => this.y(layer.lower[index])).y1(index => this.y(layer.upper[index]))
    }))
    this.plot.selectAll("path").data(this.layers, layer => layer.band).join("path").attr("stroke", "none").attr("fill", layer => category.colors[layer.band])
    this.unit.text(this.view === "percent" ? "share of the week's running" : "hours per week")
    this.categoryTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.value === this.category))
    this.viewTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.value === this.view))
    this.filtersTargets.forEach(group => (group.hidden = group.dataset.category !== this.category))
    this.#leave()
  }

  #weekX = index => this.x(this.start + index * WEEK_MS + WEEK_MS / 2)

  #resize(width) {
    this.width = width
    this.x.range([MARGIN.left, width - MARGIN.right])
    this.svg.attr("width", width)
    const plotWidth = Math.max(0, width - MARGIN.left - MARGIN.right)
    const plotHeight = HEIGHT - MARGIN.top - MARGIN.bottom
    this.y.range([HEIGHT - MARGIN.bottom, MARGIN.top])
    this.clip.attr("x", MARGIN.left).attr("y", MARGIN.top).attr("width", plotWidth).attr("height", plotHeight)
    this.overlay.attr("x", MARGIN.left).attr("y", MARGIN.top).attr("width", plotWidth).attr("height", plotHeight)
    this.cursorLine.attr("y1", MARGIN.top).attr("y2", HEIGHT - MARGIN.bottom)
    this.xAxis.attr("transform", `translate(0,${HEIGHT - MARGIN.bottom})`)
    this.yAxis.attr("transform", `translate(${MARGIN.left},0)`)
    this.plotWidth = plotWidth
    this.#render()
  }

  #setRange(range) {
    this.range = range.map(Number)
    this.#render()
  }

  #render() {
    if (!this.width || !this.range) return
    const [from, to] = this.range
    const first = weekIndex(this.start, from)
    const last = weekIndex(this.start, to - 1)
    const high = peak(this.top, first, last + 1)
    this.x.domain([from, to])
    this.y.domain([0, this.view === "percent" ? Math.min(100, (high || 1) * 1.05) : (high || 1) * 1.05]).nice(5)

    const indexes = range(Math.max(0, first - 1), Math.min(this.weeks, last + 2))
    this.plot.selectAll("path").attr("d", layer => layer.generate(indexes))

    this.yAxis.call(axisLeft(this.y).ticks(5).tickFormat(value => (this.view === "percent" ? `${value}%` : value)).tickSize(-this.plotWidth).tickSizeOuter(0))
    this.yAxis.select(".domain").remove()
    this.yAxis.selectAll(".tick line").attr("stroke", "var(--chart-grid)")
    this.yAxis.selectAll("text").attr("fill", "var(--chart-axis)")
    this.xAxis.call(axisBottom(this.x).ticks(Math.max(2, Math.floor(this.width / 110))).tickSizeOuter(0))
    this.xAxis.select(".domain").attr("stroke", "var(--chart-grid)")
    this.xAxis.selectAll(".tick line").attr("stroke", "var(--chart-grid)")
    this.xAxis.selectAll("text").attr("fill", "var(--chart-axis)")
    this.#renderHeader()
    this.#showCursor()
  }

  #renderHeader() {
    const active = activePreset(this.range, this.domain)
    this.presetTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.preset === active))
    const [from, to] = this.range
    this.rangeTarget.textContent = `${formatDate(from)} – ${formatDate(utcDay.offset(new Date(to), -1))}`
  }

  #weekAt(event) {
    return this.#clamp(weekIndex(this.start, this.x.invert(pointer(event, this.svg.node())[0])))
  }

  #clamp(week) {
    const [from, to] = this.range
    return Math.max(weekIndex(this.start, from), Math.min(weekIndex(this.start, to - 1), Math.max(0, Math.min(this.weeks - 1, week))))
  }

  #hover(event) {
    this.keyboard = false
    this.week = this.#weekAt(event)
    this.#showCursor()
    this.#tooltip(html => showTooltip(html, event))
  }

  #leave() {
    this.week = null
    this.keyboard = false
    hideTooltip()
    this.#showCursor()
  }

  #key(event) {
    if (event.key === "Escape") return this.#leave()
    const current = this.week ?? weekIndex(this.start, this.range[1] - 1)
    const target = { ArrowLeft: current - 1, ArrowRight: current + 1, Home: weekIndex(this.start, this.range[0]), End: weekIndex(this.start, this.range[1] - 1) }[event.key]
    if (target == null) return
    event.preventDefault()
    this.keyboard = true
    this.week = this.#clamp(target)
    this.#showCursor()
  }

  #tooltip(show) {
    const total = this.totals[this.category][this.week]
    if (!total) return hideTooltip()
    const rows = groupRows(this.categories[this.category], this.week, this.hidden[this.category], this.totals[this.category]).map(row => [row.label, `${formatDuration(row.seconds)} · ${Math.round(row.share)}%`])
    const from = this.start + this.week * WEEK_MS
    show(tooltipHtml(`${formatDate(from)} – ${formatDate(from + WEEK_MS - DAY_MS)}`, [...rows, ["Total", formatDuration(total)]]))
  }

  #showCursor() {
    if (!this.width) return
    const visible = this.week != null
    const position = visible ? this.#weekX(this.week) : 0
    this.cursorLine.attr("display", visible ? null : "none").attr("x1", position).attr("x2", position)
    if (this.keyboard && visible) this.#tooltip(html => showTooltipFor(html, this.cursorLine.node()))
  }

  #syncUrl() {
    const [from, to] = this.range
    const url = new URL(location.href)
    url.searchParams.set("from", new Date(from).toISOString().slice(0, 10))
    url.searchParams.set("to", utcDay.offset(new Date(to), -1).toISOString().slice(0, 10))
    url.searchParams.set("category", this.category)
    url.searchParams.set("view", this.view)
    history.replaceState(history.state, "", url)
  }
}
