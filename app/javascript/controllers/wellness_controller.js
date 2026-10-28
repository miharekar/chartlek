import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft, axisRight } from "d3-axis"
import { extent, max, quantile, range } from "d3-array"
import { pointer, select } from "d3-selection"
import { scaleLinear, scaleUtc } from "d3-scale"
import { area, curveMonotoneX, line } from "d3-shape"
import { utcDay } from "d3-time"
import { formatDate, formatDuration } from "helpers/formatters"
import { activePreset, PRESETS, presetWindow } from "helpers/pace_trends_presets"
import { observeSize } from "helpers/resize"
import { noMouseFocus } from "helpers/roving"
import { clear, publish, subscribe } from "helpers/run_cursor"
import { scrub } from "helpers/scrub"
import { createTimeline } from "helpers/timeline"
import { parseTime } from "helpers/time"
import { hideTooltip, showTooltip, showTooltipFor, tooltipHtml } from "helpers/tooltip"
import { clockLabel, dailyAverage, dayIndex, pointAtOrBefore, stackZones, weekAt, weightTrend } from "helpers/wellness"

const MARGIN = { top: 18, right: 44, bottom: 22, left: 44 }
const HEIGHT = 300
const DAY_MS = 86400000
const HALF_DAY = DAY_MS / 2
const STATUSES = ["BALANCED", "UNBALANCED", "LOW", "POOR"]
const STATUS_COLORS = { BALANCED: "var(--chart-accent)", UNBALANCED: "var(--chart-highlight)", LOW: "var(--hr-zone-5)", POOR: "var(--hr-zone-5)" }
const ZONES = [1, 2, 3, 4, 5]
const DOTS = { fill: "none", "stroke-linecap": "round" }

const dotPath = (values, view) => range(view.i0, view.i1).filter(index => values[index] != null).map(index => `M${view.xs(index).toFixed(1)},${view.y(values[index]).toFixed(1)}h0`).join("")
const linePath = (values, view) => line().defined(index => values[index] != null).x(view.xs).y(index => view.y(values[index]))(range(view.i0, view.i1))
const timePath = (points, view, curve) => line().curve(curve).x(point => view.x(point[0])).y(point => view.y(point[1]))(points)
const padded = (...series) => {
  const [low, high] = extent(series.flat())
  const pad = (high - low) * 0.05 || 1
  return [low - pad, high + pad]
}
const hours = seconds => (seconds == null ? null : seconds / 3600)
const STAGES = [["sleep_deep", "Deep", "var(--chart-accent)"], ["sleep_light", "Light", "var(--chart-accent-low)"], ["sleep_rem", "REM", "var(--chart-accent-highlight)"]]
const stageHours = (columns, index) => STAGES.map(([key]) => hours(columns[key]?.[index]) ?? 0)
const hasStages = (columns, index) => stageHours(columns, index).reduce((sum, value) => sum + value, 0) > 0
const sleepTotal = (columns, index) => (hasStages(columns, index) ? stageHours(columns, index).reduce((sum, value) => sum + value, 0) : hours(columns.sleep[index]))
const bar = (view, index, from, to, width) => `M${(view.xs(index) - width / 2).toFixed(1)},${view.y(from).toFixed(1)}h${width.toFixed(1)}V${view.y(to).toFixed(1)}h${(-width).toFixed(1)}Z`
const humanize = status => status.charAt(0) + status.slice(1).toLowerCase()

const CHARTS = {
  rhr: {
    unit: "bpm",
    layers: [{ ...DOTS, stroke: "var(--chart-muted)", "stroke-width": 4 }, { fill: "none", stroke: "var(--chart-accent)", "stroke-width": 2 }],
    domain: ({ columns }) => padded(columns.rhr),
    paths: (c, view) => [dotPath(c.columns.rhr, view), linePath(c.average, view)],
    rows: (c, index) => [["Resting HR", c.columns.rhr[index] == null ? null : `${c.columns.rhr[index]} bpm`], ["7-day average", c.average[index] == null ? null : `${Math.round(c.average[index])} bpm`]]
  },
  hrv: {
    unit: "ms",
    layers: [{ stroke: "none", fill: "var(--chart-accent)", "fill-opacity": 0.14 }, { fill: "none", stroke: "var(--chart-muted)", "stroke-width": 1 }, ...[...STATUSES, "other"].map(status => ({ ...DOTS, stroke: STATUS_COLORS[status] || "var(--chart-muted)", "stroke-width": 5 }))],
    domain: ({ columns }) => padded(columns.hrv, columns.hrv_low || [], columns.hrv_high || []),
    paths: (c, view) => {
      const { hrv, hrv_low: low, hrv_high: high, status } = c.columns
      const band = low && high ? area().defined(index => low[index] != null && high[index] != null).x(view.xs).y0(index => view.y(low[index])).y1(index => view.y(high[index]))(range(view.i0, view.i1)) : null
      return [band, linePath(hrv, view), ...c.statusDots.map(values => dotPath(values, view))]
    },
    rows: (c, index) => {
      const { hrv, hrv_low: low, hrv_high: high, status } = c.columns
      return [["Last night", hrv[index] == null ? null : `${hrv[index]} ms`], ["Baseline", low?.[index] != null && high?.[index] != null ? `${low[index]}–${high[index]} ms` : null], ["Status", status?.[index] ? humanize(status[index]) : null]]
    }
  },
  timing: {
    unit: "",
    ticks: 8,
    tickFormat: hours => clockLabel(hours * 3600),
    layers: [{ stroke: "none", fill: "var(--chart-accent-low)", "fill-opacity": 0.8 }, { fill: "none", stroke: "var(--chart-highlight)", "stroke-width": 1.5 }, { fill: "none", stroke: "var(--chart-accent)", "stroke-width": 1.5 }],
    domain: ({ columns }) => [quantile(columns.sleep_wake, 0.99) / 3600, quantile(columns.sleep_bed, 0.01) / 3600],
    paths: (c, view) => {
      const { sleep_bed: bed, sleep_wake: wake } = c.columns
      const width = Math.max(1, (view.x(view.start + DAY_MS) - view.x(view.start)) * 0.4)
      const days = range(view.i0, view.i1).filter(index => bed[index] != null && wake[index] != null)
      return [days.map(index => bar(view, index, hours(bed[index]), hours(wake[index]), width)).join(""), linePath(c.bedAverage, view), linePath(c.wakeAverage, view)]
    },
    rows: (c, index) => {
      const { sleep_bed: bed, sleep_wake: wake } = c.columns
      const inBed = c.columns.sleep_in_bed?.[index]
      return [["Fell asleep", bed[index] == null ? null : clockLabel(bed[index])], ["Woke", wake[index] == null ? null : clockLabel(wake[index])], ["Sleep window", inBed == null ? null : formatDuration(inBed)]]
    }
  },
  bb: {
    unit: "",
    layers: [{ stroke: "none", fill: "var(--chart-accent)", "fill-opacity": 0.55 }, { ...DOTS, stroke: "var(--chart-highlight)", "stroke-width": 4 }],
    domain: () => [0, 100],
    paths: (c, view) => {
      const { bb_high: high, bb_low: low, bb_wake: wake } = c.columns
      const width = Math.max(1, view.x(view.start + DAY_MS) - view.x(view.start) - 0.5)
      const days = range(view.i0, view.i1).filter(index => high[index] != null && low[index] != null)
      return [days.map(index => `M${(view.xs(index) - width / 2).toFixed(1)},${view.y(high[index]).toFixed(1)}h${width.toFixed(1)}V${view.y(low[index]).toFixed(1)}h${(-width).toFixed(1)}Z`).join(""), wake ? dotPath(wake, view) : null]
    },
    rows: (c, index) => {
      const { bb_high: high, bb_low: low, bb_wake: wake } = c.columns
      return [["High", high[index]], ["Low", low[index]], ["At wake", wake?.[index]]]
    }
  },
  sleep: {
    unit: "hours",
    secondary: { label: "Score", domain: [0, 100] },
    layers: [{ stroke: "none", fill: "var(--chart-accent-low)", "fill-opacity": 0.6 }, ...STAGES.map(([, , fill]) => ({ stroke: "none", fill })), { fill: "none", stroke: "var(--chart-axis)", "stroke-width": 1.5, "stroke-dasharray": "4 3" }, { fill: "none", stroke: "var(--chart-highlight)", "stroke-width": 1.5 }, { ...DOTS, stroke: "var(--chart-highlight)", "stroke-width": 4 }],
    domain: ({ columns }) => [0, max(columns.sleep, (_, index) => Math.max(sleepTotal(columns, index) ?? 0, hours(columns.sleep_need?.[index]) ?? 0)) || 1],
    paths: (c, view) => {
      const { columns } = c
      const width = Math.max(1, view.x(view.start + DAY_MS) - view.x(view.start) - 0.5)
      const days = range(view.i0, view.i1).filter(index => columns.sleep[index] != null)
      const unstaged = days.filter(index => !hasStages(columns, index)).map(index => bar(view, index, 0, hours(columns.sleep[index]), width)).join("")
      const staged = STAGES.map((_, stage) => days.filter(index => hasStages(columns, index)).map(index => {
        const values = stageHours(columns, index)
        const from = values.slice(0, stage).reduce((sum, value) => sum + value, 0)
        return values[stage] > 0 ? bar(view, index, from, from + values[stage], width) : ""
      }).join(""))
      const need = columns.sleep_need
      const score = columns.sleep_score
      const scoreView = { ...view, y: view.y2 }
      return [unstaged, ...staged, need ? linePath(need.map(hours), view) : null, score ? linePath(score, scoreView) : null, score ? dotPath(score, scoreView) : null]
    },
    rows: (c, index) => {
      const { columns } = c
      const staged = hasStages(columns, index)
      const seconds = key => columns[key]?.[index]
      const duration = key => (seconds(key) == null ? null : formatDuration(seconds(key)))
      return [["Sleep", duration("sleep")], ["Need", duration("sleep_need")], ...(staged ? [...STAGES.map(([key, label]) => [label, duration(key)]), ["Awake", duration("sleep_awake")]] : []), ["Score", columns.sleep_score?.[index]], ["Average heart rate", columns.sleep_hr?.[index] == null ? null : `${Math.round(columns.sleep_hr[index])} bpm`], ["Average stress", columns.sleep_stress?.[index] == null ? null : Math.round(columns.sleep_stress[index])]]
    }
  },
  stress: {
    unit: "",
    layers: [{ fill: "none", stroke: "var(--chart-accent)", "stroke-width": 1, "stroke-opacity": 0.6 }, { ...DOTS, stroke: "var(--chart-accent)", "stroke-width": 4 }],
    domain: ({ columns }) => [0, max(columns.stress) + 5],
    paths: (c, view) => [linePath(c.columns.stress, view), dotPath(c.columns.stress, view)],
    rows: (c, index) => [["Average stress", c.columns.stress[index]]]
  },
  weight: {
    unit: "kg",
    layers: [{ ...DOTS, stroke: "var(--chart-muted)", "stroke-width": 5 }, { fill: "none", stroke: "var(--chart-accent)", "stroke-width": 2 }],
    domain: ({ columns }) => padded(columns.weight),
    paths: (c, view) => [dotPath(c.columns.weight, view), linePath(c.trend, view)],
    rows: (c, index) => [["Weight", c.columns.weight[index] == null ? null : `${c.columns.weight[index].toFixed(1)} kg`], ["30-day trend", c.trend[index] == null ? null : `${c.trend[index].toFixed(1)} kg`]]
  },
  vdot: {
    unit: "",
    layers: [{ fill: "none", stroke: "var(--chart-highlight)", "stroke-width": 1.5, "stroke-opacity": 0.8 }],
    domain: ({ payload }) => padded(payload.vdot.map(point => point[1])),
    paths: (c, view) => {
      const [from, to] = c.range
      return [timePath(c.payload.vdot.filter(point => point[0] >= from && point[0] < to), view, curveMonotoneX)]
    },
    rows: (c, _, ms) => {
      const vdot = pointAtOrBefore(c.payload.vdot, ms + DAY_MS - 1)
      return [vdot && ["Top-run VDOT", vdot[1].toFixed(1)]]
    }
  },
  zones: {
    unit: "hours",
    layers: ZONES.map(zone => ({ stroke: "none", fill: `var(--hr-zone-${zone})` })),
    domain: ({ payload }) => [0, max(payload.zones, week => week.slice(1).reduce((sum, seconds) => sum + seconds, 0)) / 3600],
    paths: (c, view) => {
      const [from, to] = c.range
      const weeks = c.payload.zones.filter(week => week[0] + 7 * DAY_MS > from && week[0] < to)
      return ZONES.map(zone => weeks.map(week => {
        const { from: bottom, to: top } = stackZones(week.slice(1))[zone - 1]
        const left = view.x(week[0])
        const width = Math.max(1, view.x(week[0] + 7 * DAY_MS) - left - 1)
        return `M${left.toFixed(1)},${view.y(bottom / 3600).toFixed(1)}h${width.toFixed(1)}V${view.y(top / 3600).toFixed(1)}h${(-width).toFixed(1)}Z`
      }).join(""))
    },
    rows: (c, _, ms) => {
      const week = weekAt(c.payload.zones, ms)
      return week && [...ZONES.map(zone => [`Zone ${zone}`, formatDuration(week[zone])]), ["Total", formatDuration(week.slice(1).reduce((sum, seconds) => sum + seconds, 0))]]
    }
  }
}

export default class extends Controller {
  static targets = ["chart", "timeline", "range", "preset"]
  static values = { payload: Object }

  connect() {
    this.payload = this.payloadValue
    this.start = this.payload.start
    this.columns = this.payload.columns
    this.average = dailyAverage(this.columns.rhr || [])
    this.trend = weightTrend(this.columns.weight || [])
    this.bedAverage = dailyAverage((this.columns.sleep_bed || []).map(hours))
    this.wakeAverage = dailyAverage((this.columns.sleep_wake || []).map(hours))
    this.count = Object.values(this.columns)[0].length
    this.statusDots = this.#statusDots()
    this.domain = this.payload.domain.map(parseTime)
    this.x = scaleUtc()
    this.charts = Object.fromEntries(this.chartTargets.map(target => [target.dataset.chart, this.#build(target)]))

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
    this.unsubscribe = subscribe(day => {
      this.cursor = day
      this.#showCursor()
    })
    this.disconnectSize = observeSize(this.chartTargets[0], ({ width }) => this.#resize(width))
  }

  disconnect() {
    this.disconnectSize?.()
    this.unsubscribe?.()
    this.timeline?.destroy()
    for (const { svg } of Object.values(this.charts || {})) svg.remove()
    hideTooltip()
    clear()
  }

  preset(event) {
    const { months } = PRESETS.find(({ key }) => key === event.currentTarget.dataset.preset)
    this.timeline.setSelection(presetWindow(months, this.domain))
    this.#setRange(this.timeline.selection())
    this.#syncUrl()
  }

  #statusDots() {
    const { hrv, status } = this.columns
    const names = [...STATUSES, "other"]
    return hrv ? names.map(name => hrv.map((value, index) => ((STATUSES.includes(status?.[index]) ? status[index] : "other") === name ? value : null))) : []
  }

  #timelineData() {
    const { rhr } = this.columns
    if (!rhr) return []
    const [low] = extent(rhr)
    return rhr.flatMap((value, index) => (value == null ? [] : [{ date: new Date(this.start + index * DAY_MS), value: value - low + 4 }]))
  }

  #build(target) {
    const key = target.dataset.chart
    const spec = CHARTS[key]
    const chart = { key, spec, target, y: scaleLinear().domain(spec.domain(this)).nice(spec.ticks ?? 5) }
    if (spec.secondary) chart.y2 = scaleLinear().domain(spec.secondary.domain)
    chart.svg = select(target).append("svg").attr("class", "block w-full").attr("height", HEIGHT)
    chart.clipId = `wellness-clip-${key}-${Math.random().toString(36).slice(2)}`
    chart.clip = chart.svg.append("defs").append("clipPath").attr("id", chart.clipId).append("rect")
    chart.yAxis = chart.svg.append("g")
    chart.xAxis = chart.svg.append("g")
    if (spec.secondary) {
      chart.y2Axis = chart.svg.append("g")
      chart.y2Label = chart.svg.append("text").attr("fill", "var(--chart-axis)").attr("font-size", 11).attr("text-anchor", "end").attr("y", 10).text(spec.secondary.label)
    }
    chart.svg.append("text").attr("fill", "var(--chart-axis)").attr("font-size", 11).attr("x", MARGIN.left).attr("y", 10).text(spec.label?.(this) ?? spec.unit)
    chart.plot = chart.svg.append("g").attr("clip-path", `url(#${chart.clipId})`)
    chart.layerNodes = spec.layers.map(attributes => {
      const path = chart.plot.append("path")
      for (const [name, value] of Object.entries(attributes)) path.attr(name, value)
      return path
    })
    chart.cursorLine = chart.svg.append("line").attr("stroke", "var(--chart-highlight)").attr("stroke-width", 1.5).attr("pointer-events", "none").attr("display", "none")
    chart.overlay = chart.svg.append("rect").attr("fill", "transparent").attr("tabindex", 0).attr("role", "img").attr("aria-label", `${target.dataset.label}. Left and right arrows step through days, Escape clears.`)
      .on("mousedown", noMouseFocus)
      .call(scrub, { move: event => this.#hover(chart, event), leave: () => this.#leave() })
      .on("focus", () => this.#focus(chart))
      .on("blur", () => this.#blur(chart))
      .on("keydown", event => this.#key(chart, event))
    return chart
  }

  #resize(width) {
    this.width = width
    this.x.range([MARGIN.left, width - MARGIN.right])
    const plotWidth = Math.max(0, width - MARGIN.left - MARGIN.right)
    const plotHeight = HEIGHT - MARGIN.top - MARGIN.bottom
    for (const chart of Object.values(this.charts)) {
      chart.y.range([HEIGHT - MARGIN.bottom, MARGIN.top])
      chart.svg.attr("width", width)
      chart.clip.attr("x", MARGIN.left).attr("y", MARGIN.top).attr("width", plotWidth).attr("height", plotHeight)
      chart.overlay.attr("x", MARGIN.left).attr("y", MARGIN.top).attr("width", plotWidth).attr("height", plotHeight)
      chart.cursorLine.attr("y1", MARGIN.top).attr("y2", HEIGHT - MARGIN.bottom)
      chart.yAxis.attr("transform", `translate(${MARGIN.left},0)`).call(axisLeft(chart.y).ticks(chart.spec.ticks ?? 5).tickFormat(chart.spec.tickFormat).tickSize(-plotWidth).tickSizeOuter(0))
      chart.yAxis.select(".domain").remove()
      chart.yAxis.selectAll(".tick line").attr("stroke", "var(--chart-grid)")
      chart.yAxis.selectAll("text").attr("fill", "var(--chart-axis)")
      chart.xAxis.attr("transform", `translate(0,${HEIGHT - MARGIN.bottom})`)
      if (chart.y2) {
        chart.y2.range([HEIGHT - MARGIN.bottom, MARGIN.top])
        chart.y2Axis.attr("transform", `translate(${width - MARGIN.right},0)`).call(axisRight(chart.y2).ticks(5).tickSize(0).tickSizeOuter(0))
        chart.y2Axis.select(".domain").remove()
        chart.y2Axis.selectAll("text").attr("fill", "var(--chart-axis)")
        chart.y2Label.attr("x", width - MARGIN.right + 28)
      }
    }
    this.#render()
  }

  #setRange(range) {
    this.range = range.map(Number)
    this.#render()
  }

  #render() {
    if (!this.width) return
    const [from, to] = this.range
    this.x.domain([from, to])
    const i0 = Math.max(0, dayIndex(this.start, from) - 1)
    const i1 = Math.min(this.count, dayIndex(this.start, to) + 1)
    const xs = index => this.x(this.start + index * DAY_MS + HALF_DAY)
    for (const chart of Object.values(this.charts)) {
      const view = { x: this.x, y: chart.y, y2: chart.y2, xs, i0, i1, start: this.start }
      chart.paths = chart.spec.paths(this, view)
      chart.layerNodes.forEach((node, index) => node.attr("d", chart.paths[index]))
      chart.xAxis.call(axisBottom(this.x).ticks(Math.max(2, Math.floor(this.width / 110))).tickSizeOuter(0))
      chart.xAxis.select(".domain").attr("stroke", "var(--chart-grid)")
      chart.xAxis.selectAll(".tick line").attr("stroke", "var(--chart-grid)")
      chart.xAxis.selectAll("text").attr("fill", "var(--chart-axis)")
    }
    this.#renderHeader()
    this.#showCursor()
  }

  #renderHeader() {
    const active = activePreset(this.range, this.domain)
    this.presetTargets.forEach(button => button.setAttribute("aria-pressed", button.dataset.preset === active))
    const [from, to] = this.range
    this.rangeTarget.textContent = `${formatDate(from)} – ${formatDate(utcDay.offset(new Date(to), -1))}`
  }

  #dayAt(chart, event) {
    return utcDay.floor(this.x.invert(pointer(event, chart.svg.node())[0])).getTime()
  }

  #hover(chart, event) {
    const day = this.#dayAt(chart, event)
    this.keyboard = null
    this.#tooltip(chart, day, html => showTooltip(html, event))
    publish(day)
  }

  #leave() {
    hideTooltip()
    clear()
  }

  #focus(chart) {
    this.keyboard = chart
    publish(this.cursor ?? this.range[1] - DAY_MS)
  }

  #blur(chart) {
    if (this.keyboard === chart) this.keyboard = null
    this.#leave()
  }

  #key(chart, event) {
    const [from, to] = this.range
    const current = this.cursor ?? to - DAY_MS
    const target = { ArrowLeft: current - DAY_MS, ArrowRight: current + DAY_MS, Home: from, End: to - DAY_MS }[event.key]
    if (event.key === "Escape") return this.#leave()
    if (target == null) return
    event.preventDefault()
    this.keyboard = chart
    publish(Math.max(from, Math.min(to - DAY_MS, target)))
  }

  #tooltip(chart, day, show) {
    const rows = (chart.spec.rows(this, dayIndex(this.start, day), day) || []).filter(row => row && row[1] != null)
    if (rows.length) show(tooltipHtml(formatDate(day), rows))
    else hideTooltip()
  }

  #showCursor() {
    if (!this.width) return
    const [from, to] = this.range
    const visible = this.cursor != null && this.cursor >= from && this.cursor < to
    for (const chart of Object.values(this.charts)) {
      const position = visible ? this.x(this.cursor + HALF_DAY) : 0
      chart.cursorLine.attr("display", visible ? null : "none").attr("x1", position).attr("x2", position)
    }
    if (this.keyboard && visible) this.#tooltip(this.keyboard, this.cursor, html => showTooltipFor(html, this.keyboard.cursorLine.node()))
  }

  #syncUrl() {
    const [from, to] = this.range
    const url = new URL(location.href)
    url.searchParams.set("from", new Date(from).toISOString().slice(0, 10))
    url.searchParams.set("to", utcDay.offset(new Date(to), -1).toISOString().slice(0, 10))
    history.replaceState(history.state, "", url)
  }
}
