import { Controller } from "@hotwired/stimulus"
import { brushX } from "d3-brush"
import { scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { formatDate, formatDistance, formatDuration, formatPace } from "helpers/formatters"
import { DAY_MS, METRICS, average, axis, brushSelection, dayLabel, dayStart, edgeLabelPositions, formatValue, groupDays, lit, nextReadout, readoutText, summarize, timelineTicks, valueOrder } from "helpers/analyze_run"
import { observeSize } from "helpers/resize"
import { noMouseFocus, rovingTarget } from "helpers/roving"
import { scrub } from "helpers/scrub"
import { hideTooltip, isTooltipFor, moveTooltip, showTooltip, showTooltipFor, tooltipHtml } from "helpers/tooltip"

const MARGIN = { left: 16, right: 16 }
const STRIP = { top: 30, band: 40, height: 98 }
const TIMELINE = { top: 4, bar: 24, height: 54 }
const DOT = 8
const CURRENT_DOT = 4.5
const HIT = 10
const GLIDE = "transform 400ms ease, opacity 400ms ease"

const UNITS = { km: "km", pace: "min/km", vdot: "VDOT", hr: "bpm" }
const LABELS = { km: "distance", pace: "pace", vdot: "VDOT", hr: "heart rate" }

export default class extends Controller {
  static targets = ["strip", "timeline", "summary", "metric"]
  static values = { runs: Array, current: Object, from: Number, to: Number, metric: { type: String, default: "km" } }

  connect() {
    this.selected = null
    this.hoverDay = null
    this.hover = null
    this.focused = null
    this.mode = "share"
    this.days = groupDays(this.runsValue)
    this.stripSvg = select(this.stripTarget).append("svg").attr("class", "block")
    this.timelineSvg = select(this.timelineTarget).append("svg").attr("class", "block")
    this.onKey = event => {
      if (event.key === "Escape") this.#clear()
    }
    document.addEventListener("keydown", this.onKey)
    this.stopObserving = observeSize(this.stripTarget, ({ width }) => {
      if (width === this.width) return
      this.width = width
      this.#layout()
    })
  }

  disconnect() {
    this.stopObserving()
    document.removeEventListener("keydown", this.onKey)
    this.stripSvg.remove()
    this.timelineSvg.remove()
    hideTooltip()
  }

  metric(event) {
    this.metricValue = event.currentTarget.value
  }

  metricValueChanged() {
    this.metricTargets.forEach(button => button.setAttribute("aria-pressed", button.value === this.metricValue))
    if (!this.width) return
    hideTooltip()
    this.hoverDay = null
    this.#clear()
    this.#place(true)
  }

  #layout() {
    const { width } = this
    this.selected = null
    this.selection = null
    this.hoverDay = null
    this.#leave()
    this.x = scaleLinear().range([MARGIN.left, width - MARGIN.right])
    const svg = this.stripSvg.attr("width", width).attr("height", STRIP.height)
    svg.selectAll("*").remove()
    svg.on("mousedown.focus", noMouseFocus, true)

    this.unitLabel = svg.append("text").attr("x", MARGIN.left).attr("y", 11).attr("font-size", 11).attr("fill", "var(--chart-axis)")
    const axisTop = STRIP.top + STRIP.band
    svg.append("line").attr("x1", MARGIN.left).attr("x2", width - MARGIN.right).attr("y1", axisTop).attr("y2", axisTop).attr("stroke", "var(--chart-grid)")
    this.ticks = svg.append("g").attr("transform", `translate(0,${axisTop})`)
    this.edges = svg.append("g").attr("transform", `translate(0,${axisTop})`).attr("display", "none")
    const middle = STRIP.top + STRIP.band / 2

    this.mean = svg.append("rect").attr("x", -1).attr("width", 2).attr("y", STRIP.top + 2).attr("height", STRIP.band - 4).attr("fill", "var(--chart-accent-highlight)").attr("pointer-events", "none")
    this.dotsGroup = svg
      .append("g")
      .attr("role", "group")
      .style("outline", "none")
      .on("focus", () => this.#focusAt(this.focusPosition ?? 0))
      .on("blur", () => this.#blur())
      .on("keydown", event => this.#key(event))
    this.dots = this.dotsGroup
      .selectAll("circle")
      .data(this.runsValue)
      .join("circle")
      .attr("cx", 0)
      .attr("cy", middle)
      .attr("r", DOT)
      .attr("fill", "var(--chart-accent)")
      .attr("pointer-events", "none")
    this.currentDot = svg.append("circle").attr("cx", 0).attr("cy", middle).attr("r", CURRENT_DOT).attr("fill", "var(--chart-highlight)").attr("stroke", "currentColor").attr("stroke-width", 1.5).attr("pointer-events", "none")

    this.brush = brushX()
      .extent([
        [MARGIN.left, STRIP.top],
        [width - MARGIN.right, STRIP.top + STRIP.band]
      ])
      .on("brush end", event => this.#brushed(event.selection))
    this.brushGroup = svg.append("g").call(this.brush)
    this.brushGroup.select(".selection").attr("fill", "var(--chart-accent-highlight)").attr("fill-opacity", 0.2).attr("stroke", "var(--chart-accent-highlight)")
    this.brushGroup
      .on("mousedown.hover", () => this.#hideOwn(), true)
      .on("click", () => this.#open(this.hover))
    scrub(this.brushGroup, { mode: "tap", move: event => this.#move(event), leave: () => this.#leave() })

    this.readout = svg.append("g").attr("display", "none").style("cursor", "pointer").on("click", () => {
      this.mode = nextReadout(this.mode)
      this.#render()
    })
    this.readoutBox = this.readout.append("path").attr("class", "fill-lime-700 dark:fill-[#6ACD12]")
    this.readoutText = this.readout.append("text").attr("class", "fill-white dark:fill-zinc-950").attr("text-anchor", "middle").attr("font-size", 12).attr("font-weight", 600).attr("y", 17)

    this.#layoutTimeline()
    this.#place(false)
  }

  #place(animate) {
    const metric = this.metricValue
    const value = METRICS[metric]
    const { domain, ticks } = axis(metric, this.runsValue, this.currentValue)
    this.x.domain(domain)
    const px = known => this.x(Math.max(domain[0], Math.min(domain[1], known)))
    const glide = animate && !matchMedia("(prefers-reduced-motion: reduce)").matches ? GLIDE : "none"

    this.unitLabel.text(UNITS[metric])
    this.dots.style("transition", glide).style("transform", (run, index) => this.#shift(value(run), px, index))
    const own = value(this.currentValue)
    this.currentDot.style("transition", glide).style("transform", this.#shift(own, px, null)).style("opacity", own == null ? 0 : 1)
    const mean = average(this.runsValue, metric)
    this.meanValue = mean
    this.mean.style("transition", glide).style("transform", `translateX(${mean == null ? MARGIN.left : px(mean)}px)`)

    this.ticks.selectAll("*").remove()
    this.ticks.style("transition", "none").style("opacity", 0)
    for (const tick of ticks) {
      const group = this.ticks.append("g").attr("transform", `translate(${px(tick)},0)`)
      group.append("line").attr("y2", 4).attr("stroke", "var(--chart-axis)")
      group.append("text").attr("y", 16).attr("text-anchor", "middle").attr("font-size", 11).attr("fill", "var(--chart-axis)").text(formatValue(metric, tick))
    }
    this.ticks.node().getBoundingClientRect()
    this.ticks.style("transition", animate ? "opacity 250ms ease" : "none").style("opacity", 1)

    this.order = valueOrder(this.runsValue, metric)
    this.focusPosition = null
    this.focused = null
    this.dotsGroup.attr("tabindex", this.order.length ? 0 : -1).attr("aria-label", `Previous runs by ${LABELS[metric]}. Left and Right arrows move between runs, Enter opens the run.`)
    this.#render()
  }

  #shift(known, px, index) {
    if (known != null) return `translateX(${px(known)}px)`
    return index == null ? `translateX(${MARGIN.left}px)` : this.dots.nodes()[index].style.transform || `translateX(${MARGIN.left}px)`
  }

  #brushed(selection) {
    this.selection = selection
    this.selected = selection ? brushSelection(this.runsValue, this.metricValue, selection.map(this.x.invert).sort((a, b) => a - b)) : null
    this.#render()
  }

  #clear() {
    if (!this.brushGroup) return
    if (this.selection) this.brushGroup.call(this.brush.move, null)
  }

  #render() {
    const value = METRICS[this.metricValue]
    this.dots
      .style("opacity", (run, index) => (value(run) == null ? 0 : this.selected ? (this.selected.has(index) ? 0.6 : 0.12) : 0.35))
      .attr("stroke", (_, index) => (index === this.focused ? "var(--chart-axis)" : this.#litDots().has(index) ? "var(--chart-highlight)" : null))
      .attr("stroke-width", (_, index) => (index === this.focused ? 2 : 1.5))
    this.mean.attr("display", this.selected || this.meanValue == null ? "none" : null)
    this.ticks.attr("display", this.selected ? "none" : null)
    this.#renderEdges()
    this.#renderReadout()
    this.#paintDays()
    this.#renderSummary()
  }

  #litDots() {
    const day = this.hoverDay == null ? null : this.days[this.hoverDay]
    return new Set(day ? lit(day.indexes, this.selected) : [])
  }

  #renderEdges() {
    this.edges.selectAll("*").remove()
    this.edges.attr("display", this.selected ? null : "none")
    if (!this.selection) return
    const positions = edgeLabelPositions(this.selection, this.width)
    const [low, high] = this.x.domain()
    this.selection.forEach((position, side) => {
      this.edges.append("text").attr("x", positions[side]).attr("y", 16).attr("font-size", 11).attr("fill", "var(--chart-axis)").attr("text-anchor", side === 0 ? "end" : "start").text(formatValue(this.metricValue, Math.max(low, Math.min(high, this.x.invert(position))), true))
    })
  }

  #renderReadout() {
    this.readout.attr("display", this.selection ? null : "none")
    if (!this.selection) return
    const [from, to] = this.selection
    this.readoutText.text(readoutText(this.runsValue, this.selected, this.mode))
    const half = this.readoutText.node().getComputedTextLength() / 2 + 8
    const centre = Math.max(half, Math.min(this.width - half, (from + to) / 2))
    const tip = Math.max(-half + 8, Math.min(half - 8, (from + to) / 2 - centre))
    this.readout.attr("transform", `translate(${centre},0)`)
    this.readoutBox.attr("d", `M${-half},3H${half}V22H${tip + 5}L${tip},27L${tip - 5},22H${-half}Z`)
  }

  #layoutTimeline() {
    const { width } = this
    const run = this.currentValue
    const start = this.fromValue
    const end = dayStart(this.toValue) + DAY_MS
    this.tx = scaleLinear().domain([start, end]).range([MARGIN.left, width - MARGIN.right])
    const svg = this.timelineSvg.attr("width", width).attr("height", TIMELINE.height)
    svg.selectAll("*").remove()

    const bottom = TIMELINE.top + TIMELINE.bar
    const ticks = timelineTicks(start, this.toValue, run.race)
    ticks.forEach((tick, index) => {
      const last = index === ticks.length - 1
      if (width < 140 * ticks.length && index > 0 && !last) return
      const position = index === 0 ? this.tx(tick.t) : last ? this.tx(tick.t + DAY_MS) : this.tx(tick.t)
      svg.append("text").attr("x", position).attr("y", bottom + 18).attr("font-size", 11).attr("fill", "var(--chart-axis)").attr("text-anchor", index === 0 ? "start" : last ? "end" : "middle").text(tick.label)
    })

    const runDay = dayStart(this.toValue)
    const dayWidth = this.tx(start + DAY_MS) - this.tx(start)
    const split = this.days.some(({ day }) => day === runDay)
    const barWidth = Math.max(1.5, dayWidth - 1)
    this.dayMarks = svg
      .append("g")
      .selectAll("rect")
      .data(this.days)
      .join("rect")
      .attr("x", ({ day }) => this.tx(day))
      .attr("width", ({ day }) => (day === runDay ? barWidth / 2 : barWidth))
      .attr("y", TIMELINE.top)
      .attr("height", TIMELINE.bar)
      .attr("fill", "var(--chart-accent)")
      .style("cursor", "pointer")
      .on("click", (_, day) => {
        hideTooltip()
        this.#open(day.indexes[0])
      })
    const hoverDay = (event, day) => {
      const index = this.days.indexOf(day)
      if (index !== this.hoverDay) {
        this.hoverDay = index
        showTooltip(this.#dayHtml(day), event)
        this.#render()
      }
      moveTooltip(event)
    }
    scrub(this.dayMarks, {
      mode: "items",
      enter: hoverDay,
      move: hoverDay,
      leave: () => {
        this.hoverDay = null
        hideTooltip()
        this.#render()
      }
    })
    const ownWidth = split ? barWidth / 2 : barWidth
    const ownRun = svg
      .append("rect")
      .attr("x", this.tx(runDay) + (split ? barWidth / 2 : 0))
      .attr("width", ownWidth)
      .attr("y", TIMELINE.top)
      .attr("height", TIMELINE.bar)
      .attr("fill", "var(--chart-highlight)")
    const showOwn = event => {
      showTooltip(tooltipHtml(`${formatDate(this.toValue)} · ${dayLabel(this.toValue, this.toValue, run.race)}`, [["Distance", `${formatDistance(run.km)} km`], ["Pace", `${formatPace(run.pace)} /km`]], { heading: "This run" }), event)
      moveTooltip(event)
    }
    scrub(ownRun, { mode: "items", enter: showOwn, move: showOwn, leave: hideTooltip })
  }

  #paintDays() {
    const lights = this.selected ? new Set(this.days.map((day, index) => (lit(day.indexes, this.selected).length ? index : -1))) : null
    this.dayMarks
      .attr("fill", (_, index) => (!lights ? "var(--chart-accent)" : lights.has(index) ? "var(--chart-highlight)" : "var(--chart-muted)"))
      .attr("fill-opacity", (_, index) => (!lights || lights.has(index) ? 1 : 0.5))
      .attr("stroke", (_, index) => (index === this.hoverDay ? "var(--chart-axis)" : null))
  }

  #renderSummary() {
    const runs = this.runsValue
    const { count, km, seconds, share } = summarize(runs, this.selected || new Set(runs.map((_, index) => index)))
    const scope = this.selected ? "Selected" : "All"
    this.summaryTarget.innerHTML = `${scope}: <strong>${count}</strong> ${count === 1 ? "run" : "runs"} · <strong>${formatDistance(km)} km</strong> · <strong>${formatDuration(seconds)}</strong> · <strong>${share.toFixed(0)}%</strong> of training distance`
  }

  #hit(px, py) {
    const metric = METRICS[this.metricValue]
    const middle = STRIP.top + STRIP.band / 2
    const [low, high] = this.x.domain()
    const spot = known => this.x(Math.max(low, Math.min(high, known)))
    const own = metric(this.currentValue)
    if (own != null && Math.hypot(spot(own) - px, middle - py) <= CURRENT_DOT + 3) return "current"
    let best = null
    let nearest = HIT + DOT
    this.runsValue.forEach((run, index) => {
      const known = metric(run)
      if (known == null || Math.abs(middle - py) > DOT + 2) return
      const distance = Math.abs(spot(known) - px)
      if (distance <= nearest) {
        best = index
        nearest = distance
      }
    })
    return best
  }

  #move(event) {
    const [px, py] = pointer(event, this.stripSvg.node())
    this.hover = this.#hit(px, py)
    this.brushGroup.select(".overlay").style("cursor", this.hover == null ? "crosshair" : "pointer")
    if (this.hover == null) return this.#hideOwn()
    showTooltip(this.hover === "current" ? this.#currentHtml() : this.#dotHtml(this.runsValue[this.hover]), event)
    this.showing = true
    moveTooltip(event)
  }

  #hideOwn() {
    if (!this.showing) return
    this.showing = false
    hideTooltip()
  }

  #leave() {
    this.hover = null
    this.#hideOwn()
  }

  #open(target) {
    if (target == null || target === "current") return
    hideTooltip()
    window.Turbo.visit(this.runsValue[target].url)
  }

  #focusAt(position) {
    if (!this.order.length) return
    this.focusPosition = position
    this.focused = this.order[position]
    this.#render()
    showTooltipFor(this.#dotHtml(this.runsValue[this.focused]), this.dots.nodes()[this.focused])
  }

  #blur() {
    const node = this.focused == null ? null : this.dots.nodes()[this.focused]
    this.focused = null
    this.#render()
    if (node && isTooltipFor(node)) hideTooltip()
  }

  #key(event) {
    const position = this.focusPosition ?? 0
    const target = rovingTarget(event.key, position, this.order.length - 1)
    if (target != null) {
      event.preventDefault()
      this.#focusAt(target)
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.#open(this.order[position])
    } else if (event.key === "Escape") {
      hideTooltip()
    }
  }

  #dotHtml(run) {
    return tooltipHtml(`${formatDate(run.t)} · ${dayLabel(this.toValue, run.t, false)}`, [
      ["Distance", `${formatDistance(run.km)} km`],
      ["Pace", `${formatPace(run.pace)} /km`],
      ["Time", formatDuration(run.s)],
      ["HR", run.hr > 0 ? `${run.hr} bpm` : "–"],
      ["VDOT", run.vdot == null ? "–" : run.vdot.toFixed(1)]
    ])
  }

  #currentHtml() {
    const run = this.currentValue
    return tooltipHtml(formatDate(this.toValue), [["Distance", `${formatDistance(run.km)} km`], ["Pace", `${formatPace(run.pace)} /km`], ["VDOT", run.vdot == null ? "–" : run.vdot.toFixed(1)]], { heading: "This run" })
  }

  #dayHtml({ day, indexes }) {
    return tooltipHtml(`${formatDate(day)} · ${dayLabel(this.toValue, day, this.currentValue.race)}`, indexes.map(index => {
      const run = this.runsValue[index]
      return [`${formatDistance(run.km)} km`, `${formatPace(run.pace)} /km`]
    }))
  }
}
