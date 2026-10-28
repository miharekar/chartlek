import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft, axisRight } from "d3-axis"
import { quantile } from "d3-array"
import { interpolateRgb } from "d3-interpolate"
import { scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { line } from "d3-shape"
import { formatDistance, formatDistanceRange, formatDuration, formatPace } from "helpers/formatters"
import { drawTerrain, following, isDark, resolveColor, styleUrl } from "helpers/map_base"
import { paceScale } from "helpers/pace_scale"
import { BIN_M, bins, bucketLabels, bucketOf, buildSegments, distribution, nextSelection, segmentValue, selectionStats, selectionWeights } from "helpers/pro_map"
import { observeSize } from "helpers/resize"
import { routeAt } from "helpers/route_point"
import { clear, publish, subscribe } from "helpers/run_cursor"
import { noMouseFocus } from "helpers/roving"
import { scrub } from "helpers/scrub"
import { hideTooltip, moveTooltip, showTooltip, showTooltipFor, tooltipHtml } from "helpers/tooltip"

const PADDING = 32
const MARGIN = { top: 8, right: 44, bottom: 24, left: 44 }
const BAR_LABEL_PX = 34
const OVERLAYS = {
  hr: { key: "hr", title: "HR", unit: "bpm" },
  grade: { key: "grade", title: "Grade", unit: "%" },
  cadence: { key: "cad", title: "Cadence", unit: "spm" }
}

export default class extends Controller {
  static targets = ["map", "metric", "stats", "bars", "graph", "range", "splits"]
  static values = { data: Object, token: String, floors: Array, paceLabels: Array, metric: String }

  async connect() {
    const { d, lat = [], lng = [] } = this.dataValue
    this.segments = buildSegments(this.dataValue)
    const located = d.map((distance, index) => [distance, lng[index], lat[index]]).filter(([, longitude, latitude]) => longitude != null && latitude != null)
    this.route = located.map(([, longitude, latitude]) => [longitude, latitude])
    this.distances = located.map(([distance]) => distance)
    this.total = d.at(-1)
    this.selection = null
    this.overlayMetric = null
    this.#recompute()
    this.colors = this.metricValue ? this.#colors() : null

    this.unsubscribe = subscribe(distance => {
      this.cursor = distance
      this.#showCursor()
    })
    if (this.hasGraphTarget) {
      this.svg = select(this.graphTarget).append("svg").attr("class", "block")
      this.stopObserving = observeSize(this.graphTarget, size => {
        this.size = size
        this.#drawGraph()
      })
    }
    if (this.hasBarsTarget) {
      this.stopObservingBars = observeSize(this.barsTarget, size => {
        this.barsWidth = size.width
        if (this.barIndexes && this.#stride(this.barIndexes.length) !== this.stride) this.#buildBars()
      })
    }
    this.#renderPanels()

    const connection = (this.connection = Symbol())
    await import("mapbox-gl")
    if (this.connection !== connection) return

    const { mapboxgl } = window
    mapboxgl.accessToken = this.tokenValue
    this.scheme = matchMedia("(prefers-color-scheme: dark)")
    this.map = new mapboxgl.Map({ container: this.mapTarget, style: styleUrl(this.scheme), cooperativeGestures: matchMedia("(pointer: coarse)").matches, performanceMetricsCollection: false, bounds: this.#bounds(), fitBoundsOptions: { padding: PADDING } })
    this.map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), "top-right")
    this.map.on("style.load", () => this.#draw())
    this.changeScheme = () => {
      if (following()) this.map.setStyle(styleUrl(this.scheme), { diff: false })
    }
    this.scheme.addEventListener("change", this.changeScheme)
  }

  disconnect() {
    this.connection = null
    this.unsubscribe()
    this.stopObserving?.()
    this.stopObservingBars?.()
    this.svg?.remove()
    this.scheme?.removeEventListener("change", this.changeScheme)
    this.map?.remove()
    this.map = this.scheme = null
    hideTooltip()
    clear()
  }

  metric(event) {
    this.metricValue = event.currentTarget.value
  }

  metricValueChanged() {
    if (!this.segments) return
    this.metricTargets.forEach(button => button.setAttribute("aria-pressed", button.value === this.metricValue))
    if (this.selection?.bucket != null) this.selection = null
    this.colors = this.#colors()
    this.#recompute()
    this.#renderPanels()
    this.#showRoute()
  }

  overlay(event) {
    this.overlayMetric = OVERLAYS[event.currentTarget.value] ?? null
    this.#drawGraph()
  }

  unoverlay() {
    this.overlayMetric = null
    this.#drawGraph()
  }

  isolate(event) {
    const { from, to } = event.currentTarget.dataset
    const range = { from: Number(from), to: Number(to) }
    this.selection = this.#sameRange(range) ? null : range
    this.#select()
  }

  #select() {
    this.#recompute()
    this.#renderStats()
    this.#updateBars()
    this.#renderRows()
    this.#drawGraph()
    this.#showRoute()
  }

  #sameRange(range) {
    return this.selection?.from === range.from && this.selection?.to === range.to
  }

  #recompute() {
    this.buckets = this.metricValue ? this.segments.map(segment => bucketOf(this.metricValue, segmentValue(segment, this.metricValue), this.floorsValue)) : []
    this.weights = selectionWeights(this.segments, this.buckets, this.selection)
  }

  #renderPanels() {
    this.#renderStats()
    this.#buildBars()
    this.#renderRows()
    this.#drawGraph()
  }

  #labels() {
    return bucketLabels(this.metricValue, { floors: this.floorsValue, paceLabels: this.paceLabelsValue })
  }

  #colors() {
    const metric = this.metricValue
    const count = this.#labels().length
    if (metric === "pace") return Array.from({ length: count }, (_, index) => resolveColor(`--pace-zone-${index}`))
    if (metric === "hr") return Array.from({ length: count }, (_, index) => resolveColor(`--hr-zone-${index + 1}`))
    if (metric === "grade") {
      const [down, flat, up] = ["--hr-zone-2", "--hr-zone-3", "--hr-zone-5"].map(resolveColor)
      return Array.from({ length: count }, (_, index) => {
        const share = index / (count - 1)
        return share < 0.5 ? interpolateRgb(down, flat)(share * 2) : interpolateRgb(flat, up)((share - 0.5) * 2)
      })
    }
    const [low, high] = ["--chart-muted", "--chart-accent-highlight"].map(resolveColor)
    return Array.from({ length: count }, (_, index) => interpolateRgb(low, high)(index / (count - 1)))
  }

  #renderStats() {
    const stats = selectionStats(this.segments, this.weights)
    const parts = [`${formatDistance(stats.distance / 1000)} km`, formatDuration(stats.time)]
    if (stats.pace != null) parts.push(`${formatPace(stats.pace)} /km`)
    if (stats.hr != null) parts.push(`${Math.round(stats.hr)} bpm`)
    if (stats.cad != null) parts.push(`${Math.round(stats.cad)} spm`)
    this.statsTarget.textContent = `${this.selection ? "Selection" : "Whole run"}: ${parts.join(" · ")}`
  }

  #stride(count) {
    return Math.max(1, Math.ceil(count / Math.max(1, Math.floor((this.barsWidth ?? 0) / BAR_LABEL_PX))))
  }

  #buildBars() {
    if (!this.hasBarsTarget || !this.metricValue) return

    const focused = this.barButtons?.findIndex(({ button }) => button === document.activeElement) ?? -1
    hideTooltip()
    const labels = this.#labels()
    const totals = distribution(this.segments, this.buckets, labels.length)
    const used = totals.map((total, index) => (total.time > 0 ? index : null)).filter(index => index != null)
    this.barButtons = []
    this.barIndexes = []
    if (!used.length) return this.barsTarget.replaceChildren()

    const colors = this.colors
    const indexes = (this.barIndexes = Array.from({ length: used.at(-1) - used[0] + 1 }, (_, offset) => used[0] + offset))
    const peak = Math.max(...totals.map(total => total.time))
    const sum = totals.reduce((sum, total) => sum + total.time, 0)
    const stride = (this.stride = this.#stride(indexes.length))

    this.barButtons = indexes.map((index, position) => {
      const share = totals[index].time / sum
      const button = document.createElement("button")
      button.type = "button"
      button.className = "flex min-w-0 flex-1 cursor-pointer flex-col justify-end gap-1 text-xs tabular-nums text-zinc-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-600 dark:text-zinc-400"
      button.setAttribute("aria-label", `${labels[index].title}, ${(share * 100).toFixed(1)}% of the time`)
      const bar = document.createElement("span")
      bar.className = "block min-h-px rounded-t-sm"
      bar.style.height = `${(totals[index].time / peak) * 100}%`
      bar.style.background = colors[index]
      const text = document.createElement("span")
      text.className = "flex h-4 justify-center whitespace-nowrap"
      text.textContent = position % stride === 0 ? labels[index].label : ""
      button.append(bar, text)
      button.addEventListener("click", () => {
        this.selection = nextSelection(this.selection, index)
        this.#select()
      })
      const showBar = event => {
        showTooltip(tooltipHtml(labels[index].title, [["Time", `${formatDuration(totals[index].time)} (${(share * 100).toFixed(1)}%)`], ["Distance", `${formatDistance(totals[index].distance / 1000)} km`]]), event)
        moveTooltip(event)
      }
      scrub(select(button), { mode: "items", enter: showBar, move: showBar, leave: hideTooltip })
      return { button, bar, index }
    })
    this.barsTarget.replaceChildren(...this.barButtons.map(({ button }) => button))
    this.#updateBars()
    if (focused >= 0) this.barButtons[Math.min(focused, this.barButtons.length - 1)].button.focus({ preventScroll: true })
  }

  #updateBars() {
    if (!this.barButtons) return

    const reached = new Set(this.weights ? this.buckets.filter((bucket, segment) => bucket != null && this.weights[segment] > 0) : [])
    for (const { button, bar, index } of this.barButtons) {
      button.setAttribute("aria-pressed", this.selection?.bucket === index)
      bar.style.opacity = !this.weights || reached.has(index) ? 1 : 0.3
    }
  }

  #renderRows() {
    for (const row of this.rangeTargets) {
      const range = { from: Number(row.dataset.from), to: Number(row.dataset.to) }
      row.querySelector("button").setAttribute("aria-pressed", this.#sameRange(range))
    }
    if (this.hasSplitsTarget) {
      for (const cell of this.splitsTarget.querySelectorAll("[data-metric]")) cell.hidden = Boolean(this.metricValue) && cell.dataset.metric !== this.metricValue
    }
  }

  #drawGraph() {
    if (!this.svg || !this.size) return

    const { width, height } = this.size
    const data = bins(this.segments, this.weights)
    if (!data.length || !width) return

    const innerWidth = width - MARGIN.left - MARGIN.right
    if (innerWidth <= 0) return

    const innerHeight = height - MARGIN.top - MARGIN.bottom
    const paced = data.filter(bin => bin.pace != null)
    if (!paced.length) return

    const paces = paced.map(bin => bin.pace).sort((a, b) => a - b)
    const x = scaleLinear().domain([0, this.total / 1000]).range([0, innerWidth])
    const y = paceScale([quantile(paces, 0.01) * 0.95, quantile(paces, 0.99) * 1.05], [0, innerHeight])
    const top = pace => Math.min(innerHeight, Math.max(0, y(pace)))

    const refocus = this.graphFocused
    this.redrawing = true
    this.svg.attr("width", width).attr("height", height).selectAll("*").remove()
    const chart = this.svg.append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)
    const yAxis = chart.append("g").call(axisLeft(y).ticks(5).tickSize(-innerWidth))
    const xAxis = chart.append("g").attr("transform", `translate(0,${innerHeight})`).call(axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 80))).tickFormat(value => `${value} km`).tickSize(4))
    const axes = [xAxis, yAxis]

    chart.append("g").selectAll("rect").data(paced).join("rect")
      .attr("x", bin => x(bin.from / 1000))
      .attr("width", bin => Math.max(1, x(bin.distance / 1000) - 1))
      .attr("y", bin => top(bin.pace))
      .attr("height", bin => innerHeight - top(bin.pace))
      .attr("fill", bin => (bin.selected ? "var(--chart-accent)" : "var(--chart-muted)"))

    const overlay = this.overlayMetric
    let overlayAxis = null
    if (overlay && data.some(bin => bin[overlay.key] != null)) {
      const values = data.map(bin => bin[overlay.key]).filter(value => value != null)
      const low = Math.min(...values)
      const high = Math.max(...values)
      const pad = (high - low || 1) * 0.1
      const y2 = scaleLinear().domain([low - pad, high + pad]).range([innerHeight, 0])
      const axis = chart.append("g").attr("transform", `translate(${innerWidth},0)`).call(axisRight(y2).ticks(5).tickSize(4))
      overlayAxis = axis
      axes.push(axis)
      chart.append("path").attr("fill", "none").attr("stroke", "var(--chart-highlight)").attr("stroke-width", 2).attr("pointer-events", "none")
        .attr("d", line().defined(bin => bin[overlay.key] != null).x(bin => x((bin.from + bin.distance / 2) / 1000)).y(bin => y2(bin[overlay.key]))(data))
      chart.append("text").attr("x", innerWidth).attr("y", -1).attr("text-anchor", "end").attr("font-size", 10).attr("fill", "var(--chart-highlight)").text(`${overlay.title} (${overlay.unit})`)
    }

    for (const axis of axes) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }
    xAxis.selectAll("line").attr("stroke", "var(--chart-axis)")
    overlayAxis?.selectAll("text").attr("fill", "var(--chart-highlight)")

    this.graphBins = data
    this.cursorX = x
    this.cursorLine = chart.append("line").attr("y1", 0).attr("y2", innerHeight).attr("stroke", "var(--chart-highlight)").attr("stroke-width", 1.5).attr("pointer-events", "none").attr("display", "none")
    this.#showCursor()

    const overlayRect = chart.append("rect").attr("width", innerWidth).attr("height", innerHeight).attr("fill", "none").attr("pointer-events", "all").attr("tabindex", 0).attr("role", "img").attr("aria-label", "Change in pace. Left and right arrows move along the route, Home and End jump to the ends, Escape clears.").style("outline-offset", "-2px")
      .on("mousedown", noMouseFocus)
      .call(scrub, {
        move: event => {
          this.keyboard = false
          const position = x.invert(pointer(event)[0]) * 1000
          showTooltip(this.#tooltipHtml(this.#binAt(position)), event)
          moveTooltip(event)
          publish(position)
        },
        leave: () => {
          hideTooltip()
          clear()
        }
      })
      .on("focus", () => {
        this.graphFocused = this.keyboard = true
        if (!this.redrawing) publish(this.cursor ?? data[0].from)
      })
      .on("blur", event => {
        if (this.redrawing || !event.target.isConnected) return

        this.graphFocused = this.keyboard = false
        hideTooltip()
        clear()
      })
      .on("keydown", event => this.#key(event))
    if (refocus) overlayRect.node().focus({ preventScroll: true })
    this.redrawing = false
  }

  #binAt(position) {
    return this.graphBins[Math.max(0, this.graphBins.findLastIndex(entry => entry.from <= position))]
  }

  #key(event) {
    if (event.altKey || event.ctrlKey || event.metaKey) return

    const first = this.graphBins[0].from
    const current = this.cursor ?? first - BIN_M
    const target = { ArrowLeft: current - BIN_M, ArrowRight: current + BIN_M, Home: first, End: this.total }[event.key]
    if (event.key === "Escape") {
      hideTooltip()
      return clear()
    }
    if (target == null) return

    event.preventDefault()
    this.keyboard = true
    publish(Math.max(first, Math.min(this.total, target)))
  }

  #tooltipHtml(bin) {
    return tooltipHtml(formatDistanceRange(bin.from / 1000, (bin.from + bin.distance) / 1000), [
      bin.pace != null && ["Pace", `${formatPace(bin.pace)} /km`],
      bin.hr != null && ["HR", `${Math.round(bin.hr)} bpm`],
      bin.cad != null && ["Cadence", `${Math.round(bin.cad)} spm`],
      bin.grade != null && ["Grade", `${bin.grade.toFixed(1)}%`]
    ])
  }

  #showCursor() {
    if (this.cursorLine) {
      if (this.cursor == null) {
        this.cursorLine.attr("display", "none")
      } else {
        const [start, end] = this.cursorX.domain()
        const position = this.cursorX(Math.max(start, Math.min(end, this.cursor / 1000)))
        this.cursorLine.attr("display", null).attr("x1", position).attr("x2", position)
      }
    }
    if (this.keyboard && this.cursor != null && this.cursorLine) showTooltipFor(this.#tooltipHtml(this.#binAt(this.cursor)), this.cursorLine.node())
    this.map?.getSource("cursor")?.setData(this.#cursorData())
  }

  #cursorData() {
    const point = this.cursor == null ? null : routeAt(this.route, this.distances, this.cursor)
    return { type: "FeatureCollection", features: point ? [{ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: point } }] : [] }
  }

  #bounds() {
    const longitudes = this.route.map(([longitude]) => longitude)
    const latitudes = this.route.map(([, latitude]) => latitude)
    return [[Math.min(...longitudes), Math.min(...latitudes)], [Math.max(...longitudes), Math.max(...latitudes)]]
  }

  #draw() {
    drawTerrain(this.map, isDark(this.scheme))
    this.colors = this.metricValue ? this.#colors() : null
    this.#buildBars()
    this.map.addSource("route", { type: "geojson", data: this.#routeData() })
    for (const [id, on, opacity] of [["route-dim", false, 0.25], ["route", true, 1]]) {
      this.map.addLayer({ id, type: "line", source: "route", filter: ["==", ["get", "on"], on], layout: { "line-join": "round", "line-cap": "round" }, paint: { "line-color": ["get", "color"], "line-width": 5, "line-opacity": opacity } })
    }
    this.map.addSource("cursor", { type: "geojson", data: this.#cursorData() })
    this.map.addLayer({ id: "cursor-halo", type: "circle", source: "cursor", paint: { "circle-radius": 13, "circle-color": resolveColor("--chart-highlight"), "circle-opacity": 0.35 } })
    this.map.addLayer({ id: "cursor", type: "circle", source: "cursor", paint: { "circle-radius": 6, "circle-color": resolveColor("--chart-highlight"), "circle-stroke-color": "#ffffff", "circle-stroke-width": 2 } })
  }

  #showRoute() {
    this.map?.getSource("route")?.setData(this.#routeData())
  }

  #routeData() {
    const colors = this.colors
    const accent = resolveColor("--chart-accent")
    const features = []

    this.segments.forEach((segment, index) => {
      if (!segment.line) return

      const color = colors && this.buckets[index] != null ? colors[this.buckets[index]] : accent
      const on = this.weights ? this.weights[index] >= 0.5 : true
      const last = features.at(-1)
      const [start, end] = segment.line
      const coordinates = last?.geometry.coordinates
      if (last && last.properties.color === color && last.properties.on === on && coordinates.at(-1)[0] === start[0] && coordinates.at(-1)[1] === start[1]) {
        coordinates.push(end)
      } else {
        features.push({ type: "Feature", properties: { color, on }, geometry: { type: "LineString", coordinates: [start, end] } })
      }
    })
    return { type: "FeatureCollection", features }
  }
}
