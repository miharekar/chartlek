import { Controller } from "@hotwired/stimulus"
import { max, min, quantile } from "d3-array"
import { Delaunay } from "d3-delaunay"
import { pointer, select } from "d3-selection"
import { scaleLog } from "d3-scale"
import { line } from "d3-shape"
import { utcDay, utcMonth } from "d3-time"
import { formatDate, formatDistance, formatDuration, formatPace } from "helpers/formatters"
import { paceScale } from "helpers/pace_scale"
import { daysSince, daysSincePr, magicText, parseRuns, percentSlower, predictions, recordsByBucket, windowBest } from "helpers/pr_progress"
import { observeSize } from "helpers/resize"
import { scrub } from "helpers/scrub"
import { createTimeline } from "helpers/timeline"
import { escapeHtml, hideTooltip, moveTooltip, showTooltip } from "helpers/tooltip"
import { parseTime } from "helpers/time"

const MARGIN = { top: 12, right: 28, bottom: 40, left: 56 }
const DOT_RADIUS = 8
const MARKER_RADIUS = 14
const X_LABELS = [
  [3, "3 km"],
  [5, "5 km"],
  [10, "10 km"],
  [21.0975, "Half"],
  [42.195, "Marathon"],
  [100, "100 km"]
]

const CELL = "px-3 py-2"
const HEAD = "px-3 py-2 text-left font-medium"
const MUTED = "text-zinc-500 dark:text-zinc-400"
const TABLE_LINK = "hover:text-lime-700 hover:underline dark:hover:text-[#9CFF44]"
const CHIP = "rounded px-1.5 py-0.5 text-xs font-medium bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300"

export default class extends Controller {
  static targets = ["chart", "timeline", "table", "range", "beat", "magic", "reference", "legend"]
  static values = { data: Object, mode: String, days: Number }

  connect() {
    this.build()
  }

  disconnect() {
    this.teardown()
  }

  setMode(event) {
    this.mode = event.currentTarget.dataset.mode
    this.syncControls()
    this.drawOverlay()
  }

  setDays(event) {
    this.days = Number(event.currentTarget.dataset.days)
    this.referenceId = this.references[this.days]
    this.syncControls()
    this.drawOverlay()
  }

  build() {
    const data = this.dataValue
    this.mode = this.modeValue
    this.days = this.daysValue
    this.runs = parseRuns(data)
    this.benchmarks = data.benchmarks
    this.records = recordsByBucket(data.frontier, this.benchmarks.length)
    this.frontier = data.frontier
    this.magic = data.magic
    this.references = data.references
    this.referenceId = this.references[this.days]
    this.byId = new Map(this.runs.map(run => [run.id, run]))
    this.markers = { frontier: [], window: [], overlay: [] }
    this.hovered = null
    this.setScales()

    const today = parseTime(data.today)
    this.timeline = createTimeline(this.timelineTarget, {
      data: this.runs.map(run => ({ date: parseTime(run.time), value: 1 })),
      domain: [parseTime(data.first), today],
      selection: [utcMonth.offset(today, -12), utcDay.offset(today, 1)],
      onBrush: range => this.setWindow(range),
      onEnd: range => this.setWindow(range)
    })
    this.window = this.timeline.selection().map(Number)
    this.stopObserving = observeSize(this.chartTarget, ({ width }) => {
      if (width === this.width) return
      this.width = width
      this.drawChart(width)
    })
    this.syncControls()
  }

  teardown() {
    this.stopObserving?.()
    this.timeline?.destroy()
    select(this.chartTarget).selectAll("svg").remove()
    hideTooltip()
  }

  setScales() {
    const distances = this.runs.map(run => run.distance).sort((a, b) => a - b)
    const lowest = Math.min(1.2, Math.max(0.5, quantile(distances, 0.01) * 0.9))
    const longest = max(distances)
    this.xDomain = [lowest, longest * 1.12]
    this.reachable = new Set(this.benchmarks.flatMap(({ meters }, bucket) => (meters / 1000 <= longest ? [bucket] : [])))

    const visible = this.runs.filter(run => run.distance >= lowest)
    const peak = max(this.runs, run => run.vdot)
    const paces = visible.map(run => run.pace).concat(this.frontier.map(record => record.pace))
    for (const row of predictions(this.benchmarks, this.records, peak)) if (this.reachable.has(row.bucket)) paces.push(row.pace)
    for (const target of this.magic) paces.push((target.target / this.benchmarks[target.bucket].meters) * 1000)
    this.paceDomain = [min(paces) * 0.97, Math.min(quantile(visible.map(run => run.pace).sort((a, b) => a - b), 0.995), 1200) * 1.03]
  }

  setWindow(range) {
    this.window = range.map(Number)
    this.drawWindow()
  }

  drawChart(width) {
    if (width - MARGIN.left - MARGIN.right <= 0) return

    const height = width < 640 ? 360 : 460
    const x = scaleLog().domain(this.xDomain).range([MARGIN.left, width - MARGIN.right])
    const y = paceScale(this.paceDomain, [MARGIN.top, height - MARGIN.bottom])
    const slowest = this.paceDomain[1]
    this.px = distanceKm => x(distanceKm)
    this.py = pace => y(Math.min(pace, slowest))

    select(this.chartTarget).selectAll("svg").remove()
    const svg = select(this.chartTarget).append("svg").attr("class", "block w-full").attr("width", width).attr("height", height)
    this.drawAxes(svg, x, y, width, height)
    this.drawDots(svg)
    this.windowLayer = svg.append("g")
    this.drawFrontier(svg)
    this.overlayLayer = svg.append("g")
    this.ring = svg.append("circle").attr("r", 7).attr("fill", "none").attr("stroke", "var(--chart-axis)").attr("stroke-width", 1.5).attr("pointer-events", "none").attr("display", "none")
    this.surface = svg
      .append("rect")
      .attr("x", MARGIN.left)
      .attr("y", MARGIN.top)
      .attr("width", width - MARGIN.left - MARGIN.right)
      .attr("height", height - MARGIN.top - MARGIN.bottom)
      .attr("fill", "transparent")
      .call(scrub, { move: event => this.hover(event), leave: () => this.leave() })
      .on("click", event => this.pick(event))

    this.drawWindow()
    this.drawOverlay()
  }

  drawAxes(svg, x, y, width, height) {
    const grid = svg.append("g").attr("stroke", "var(--chart-grid)")
    const labels = svg.append("g").attr("fill", "var(--chart-axis)").attr("font-size", 11)
    const bottom = height - MARGIN.bottom

    for (const pace of y.ticks(8)) {
      if (pace < this.paceDomain[0] || pace > this.paceDomain[1]) continue
      grid.append("line").attr("x1", MARGIN.left).attr("x2", width - MARGIN.right).attr("y1", y(pace)).attr("y2", y(pace))
      labels.append("text").attr("x", MARGIN.left - 8).attr("y", y(pace)).attr("dy", "0.32em").attr("text-anchor", "end").text(formatPace(pace))
    }

    let previous = -Infinity
    for (const [km, label] of X_LABELS) {
      if (km < this.xDomain[0] || km > this.xDomain[1] || x(km) - previous < 44) continue
      previous = x(km)
      grid.append("line").attr("x1", x(km)).attr("x2", x(km)).attr("y1", MARGIN.top).attr("y2", bottom)
      labels.append("text").attr("x", x(km)).attr("y", bottom + 16).attr("text-anchor", "middle").text(label)
    }

    labels.append("text").attr("x", MARGIN.left - 8).attr("y", MARGIN.top - 2).attr("text-anchor", "end").attr("font-size", 10).text("min/km")
  }

  drawDots(svg) {
    this.dots = this.runs.filter(run => run.distance >= this.xDomain[0])
    this.positions = this.dots.map(run => [this.px(run.distance), this.py(run.pace)])
    this.delaunay = Delaunay.from(this.positions)
    svg
      .append("g")
      .attr("fill", "var(--chart-muted)")
      .attr("fill-opacity", 0.6)
      .selectAll("circle")
      .data(this.positions)
      .join("circle")
      .attr("cx", position => position[0])
      .attr("cy", position => position[1])
      .attr("r", 2.4)
  }

  drawFrontier(svg) {
    const points = this.frontier.map(record => this.point(record.bucket, record.pace))
    const group = svg.append("g")
    group.append("path").attr("d", line()(points)).attr("fill", "none").attr("stroke", "var(--chart-accent)").attr("stroke-width", 2.5).attr("stroke-linejoin", "round")
    group.append("g").attr("fill", "var(--chart-accent)").selectAll("circle").data(points).join("circle").attr("cx", point => point[0]).attr("cy", point => point[1]).attr("r", 4.5)
    this.markers.frontier = this.frontier.map((record, index) => ({ x: points[index][0], y: points[index][1], html: this.frontierHtml(record) }))
  }

  drawWindow() {
    if (!this.windowLayer) return
    const best = windowBest(this.runs, this.window, this.benchmarks.length)
    const since = daysSince(this.runs, this.window[1], this.benchmarks.length)
    const sincePr = daysSincePr(this.runs, this.window[1], this.benchmarks.length)
    const points = []
    this.markers.window = []
    best.forEach((run, bucket) => {
      if (!run) return
      const point = this.point(bucket, (run.best / this.benchmarks[bucket].meters) * 1000)
      points.push(point)
      this.markers.window.push({ x: point[0], y: point[1], html: this.windowHtml(bucket, run) })
    })

    this.windowLayer.selectAll("*").remove()
    this.windowLayer.append("path").attr("d", line()(points)).attr("fill", "none").attr("stroke", "var(--chart-accent-highlight)").attr("stroke-width", 2).attr("stroke-dasharray", "6 4")
    this.windowLayer.append("g").attr("fill", "none").attr("stroke", "var(--chart-accent-highlight)").attr("stroke-width", 2).selectAll("circle").data(points).join("circle").attr("cx", point => point[0]).attr("cy", point => point[1]).attr("r", 4)

    this.renderRange()
    this.renderTable(best, since, sincePr)
  }

  drawOverlay() {
    if (!this.overlayLayer) return
    this.overlayLayer.selectAll("*").remove()
    this.markers.overlay = []
    if (this.mode === "beat") this.drawPredictions()
    if (this.mode === "magic") this.drawMagic()
    this.renderLegend()
  }

  drawPredictions() {
    const reference = this.byId.get(this.referenceId)
    this.renderReference(reference)
    if (!reference) return

    const rows = predictions(this.benchmarks, this.records, reference.vdot).filter(row => this.reachable.has(row.bucket))
    const points = rows.map(row => this.point(row.bucket, row.pace))
    this.overlayLayer.append("path").attr("d", line()(points)).attr("fill", "none").attr("stroke", "var(--chart-highlight)").attr("stroke-width", 2).attr("stroke-opacity", 0.8)
    this.overlayLayer
      .append("g")
      .selectAll("circle")
      .data(rows)
      .join("circle")
      .attr("cx", (row, index) => points[index][0])
      .attr("cy", (row, index) => points[index][1])
      .attr("r", 5)
      .attr("stroke", "var(--chart-highlight)")
      .attr("stroke-width", 2)
      .attr("fill", row => (row.beats ? "var(--chart-highlight)" : "none"))
    this.markers.overlay = rows.map((row, index) => ({ x: points[index][0], y: points[index][1], html: this.predictionHtml(row, reference) }))

    const [rx, ry] = [this.px(reference.distance), this.py(reference.pace)]
    this.overlayLayer.append("circle").attr("cx", rx).attr("cy", ry).attr("r", 9).attr("fill", "none").attr("stroke", "var(--chart-highlight)").attr("stroke-width", 2)
    this.overlayLayer.append("circle").attr("cx", rx).attr("cy", ry).attr("r", 3.5).attr("fill", "var(--chart-highlight)")
  }

  drawMagic() {
    for (const target of this.magic) {
      const { meters, name } = this.benchmarks[target.bucket]
      const record = this.records[target.bucket]
      const from = this.point(target.bucket, record.pace)
      const to = this.point(target.bucket, (target.target / meters) * 1000)
      this.overlayLayer.append("line").attr("x1", from[0]).attr("y1", from[1]).attr("x2", to[0]).attr("y2", to[1]).attr("stroke", "var(--chart-highlight)").attr("stroke-width", 1.5).attr("stroke-dasharray", "3 3")
      this.overlayLayer.append("circle").attr("class", "motion-safe:animate-ping origin-center [transform-box:fill-box]").attr("cx", to[0]).attr("cy", to[1]).attr("r", 6).attr("fill", "var(--chart-highlight)").attr("fill-opacity", 0.55)
      this.overlayLayer.append("circle").attr("cx", to[0]).attr("cy", to[1]).attr("r", 5.5).attr("fill", "var(--chart-highlight)")
      this.markers.overlay.push({ x: to[0], y: to[1], html: `<div class="font-medium">${escapeHtml(magicText(name, target.target, record.time, target.percent))}</div><div class="${MUTED}">PR ${formatDuration(record.time)} · target pace ${formatPace((target.target / meters) * 1000)} /km</div>` })
    }
  }

  hover(event) {
    const [x, y] = pointer(event)
    const marker = this.nearestMarker(x, y)
    const index = marker ? null : this.nearestDot(x, y)
    const target = marker || (index != null ? { x: this.positions[index][0], y: this.positions[index][1], html: this.runHtml(this.dots[index]) } : null)

    if (!target) return this.leave()
    this.ring.attr("cx", target.x).attr("cy", target.y).attr("display", null)
    this.surface.style("cursor", this.mode === "beat" && index != null ? "pointer" : "default")
    const key = marker || index
    if (key === this.hovered) return moveTooltip(event)
    this.hovered = key
    showTooltip(target.html, event)
  }

  leave() {
    this.hovered = null
    this.ring?.attr("display", "none")
    hideTooltip()
  }

  pick(event) {
    if (this.mode !== "beat") return
    const [x, y] = pointer(event)
    const index = this.nearestDot(x, y)
    const run = index != null && this.dots[index]
    if (!run || run.vdot == null) return
    this.referenceId = run.id
    this.days = null
    this.syncControls()
    this.drawOverlay()
  }

  nearestMarker(x, y) {
    let nearest
    let nearestDistance = MARKER_RADIUS
    for (const marker of [...this.markers.overlay, ...this.markers.window, ...this.markers.frontier]) {
      const distance = Math.hypot(marker.x - x, marker.y - y)
      if (distance < nearestDistance) [nearest, nearestDistance] = [marker, distance]
    }
    return nearest
  }

  nearestDot(x, y) {
    const index = this.delaunay.find(x, y)
    return Math.hypot(this.positions[index][0] - x, this.positions[index][1] - y) <= DOT_RADIUS ? index : null
  }

  point(bucket, pace) {
    return [this.px(this.benchmarks[bucket].meters / 1000), this.py(pace)]
  }

  frontierHtml(record) {
    const { name, meters } = this.benchmarks[record.bucket]
    return `<div class="font-medium">${escapeHtml(name)} PR${record.race ? ` ${this.tag("Race")}` : ""}</div><div>${formatDuration(record.time)} · ${formatPace((record.time / meters) * 1000)} /km</div><div class="${MUTED}">${formatDate(record.date)} · ${escapeHtml(record.name || "")}</div>`
  }

  windowHtml(bucket, run) {
    const { name, meters } = this.benchmarks[bucket]
    const record = this.records[bucket]
    const versus = run.best <= record.time ? this.tag("PR") : `+${percentSlower(run.best, record.time).toFixed(1)}% vs PR`
    return `<div class="font-medium">Best in window · ${escapeHtml(name)}</div><div>${formatDuration(run.best)} · ${formatPace((run.best / meters) * 1000)} /km · ${versus}</div><div class="${MUTED}">${formatDate(run.time)} · ${escapeHtml(run.name || "")}</div>`
  }

  predictionHtml(row, reference) {
    const { name } = this.benchmarks[row.bucket]
    const record = this.records[row.bucket]
    let versus = `<div class="${MUTED}">No PR yet</div>`
    if (record) {
      const faster = row.change >= 0
      versus = `<div class="${MUTED}">${Math.abs(row.change).toFixed(1)}% ${faster ? "faster" : "slower"} than your PR (${formatDuration(record.time)})</div>`
    }
    return `<div class="font-medium">Predicted ${escapeHtml(name)} at VDOT ${reference.vdot.toFixed(1)}</div><div>${formatDuration(row.time)} · ${formatPace(row.pace)} /km</div>${versus}`
  }

  runHtml(run) {
    const vdot = run.vdot == null ? "" : ` · VDOT ${run.vdot.toFixed(1)}`
    return `<div class="font-medium">${escapeHtml(run.name || "Run")}${run.race ? ` ${this.tag("Race")}` : ""}</div><div>${formatDistance(run.distance)} km · ${formatPace(run.pace)} /km${vdot}</div><div class="${MUTED}">${formatDate(run.time)}</div>`
  }

  tag(label) {
    return `<span class="${CHIP}">${label}</span>`
  }

  syncControls() {
    this.element.querySelectorAll("[data-mode]").forEach(button => button.setAttribute("aria-pressed", button.dataset.mode === this.mode))
    this.element.querySelectorAll("[data-days]").forEach(button => button.setAttribute("aria-pressed", Number(button.dataset.days) === this.days))
    this.beatTarget.classList.toggle("hidden", this.mode !== "beat")
    this.beatTarget.classList.toggle("flex", this.mode === "beat")
    this.magicTarget.classList.toggle("hidden", this.mode !== "magic")
  }

  renderReference(reference) {
    if (!reference) {
      this.referenceTarget.textContent = `No run with a VDOT in the last ${this.days || "selected"} days.`
      return
    }
    this.referenceTarget.innerHTML = `${formatDate(reference.time)} · ${escapeHtml(reference.name || "Run")} · ${formatDistance(reference.distance)} km at ${formatPace(reference.pace)} /km · VDOT ${reference.vdot.toFixed(1)} <a href="${escapeHtml(reference.url)}" class="underline">open</a> · click any run to use it instead`
  }

  renderRange() {
    const [start, end] = this.window
    const count = this.runs.filter(run => run.time >= start && run.time < end).length
    this.rangeTarget.textContent = `${formatDate(start)} – ${formatDate(end - 1)} · ${count} ${count === 1 ? "run" : "runs"}`
  }

  renderLegend() {
    const dot = (color, label, extra = "") => `<span class="inline-flex items-center gap-1.5"><span class="inline-block size-2 rounded-full ${extra}" style="background:${color}"></span>${label}</span>`
    const bar = (color, label, style = "solid") => `<span class="inline-flex items-center gap-1.5"><span class="inline-block w-4 border-t-2 border-${style}" style="border-color:${color}"></span>${label}</span>`
    const items = [dot("var(--chart-muted)", "Runs"), bar("var(--chart-accent)", "All-time PRs"), bar("var(--chart-accent-highlight)", "Best in window", "dashed")]
    if (this.mode === "beat") items.push(dot("var(--chart-highlight)", "Prediction beats PR"), `<span class="inline-flex items-center gap-1.5"><span class="inline-block size-2 rounded-full border-2" style="border-color:var(--chart-highlight)"></span>Not yet</span>`)
    if (this.mode === "magic") items.push(dot("var(--chart-highlight)", "Magic target"))
    this.legendTarget.innerHTML = items.join("")
  }

  renderTable(best, since, sincePr) {
    const rows = this.benchmarks.map((benchmark, bucket) => this.row(benchmark, bucket, best[bucket], since[bucket], sincePr[bucket])).join("")
    this.tableTarget.innerHTML = `<thead class="${MUTED}"><tr class="border-b border-zinc-200 dark:border-zinc-800"><th class="${HEAD}">Distance</th><th class="${HEAD}">All-time PR</th><th class="${HEAD}">Best in window</th><th class="${HEAD}">vs PR</th><th class="${HEAD} text-right">Days since last run</th><th class="${HEAD} text-right">Days since PR</th></tr></thead><tbody class="divide-y divide-zinc-100 dark:divide-zinc-800/60">${rows}</tbody>`
  }

  row({ name }, bucket, best, since, sincePr) {
    const record = this.records[bucket]
    if (!record) return ""

    const versus = best ? (best.best <= record.time ? this.tag("PR") : `+${percentSlower(best.best, record.time).toFixed(1)}%`) : `<span class="${MUTED}">–</span>`
    const days = since == null ? `<span class="${MUTED}">–</span>` : since
    const prDays = sincePr == null ? `<span class="${MUTED}">–</span>` : sincePr
    return `<tr class="hover:bg-zinc-50 dark:hover:bg-zinc-800/40"><td class="${CELL} font-medium">${escapeHtml(name)}</td><td class="${CELL}">${this.cell(record.time, record.date, record.url)}</td><td class="${CELL}">${best ? this.cell(best.best, best.time, best.url) : `<span class="${MUTED}">–</span>`}</td><td class="${CELL}">${versus}</td><td class="${CELL} text-right">${days}</td><td class="${CELL} text-right">${prDays}</td></tr>`
  }

  cell(time, date, url) {
    return `<a href="${escapeHtml(url)}" class="${TABLE_LINK}">${formatDuration(time)}</a> <span class="${MUTED}">${formatDate(date)}</span>`
  }
}
