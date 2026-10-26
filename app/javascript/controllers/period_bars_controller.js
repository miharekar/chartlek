import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { max } from "d3-array"
import { scaleBand, scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { utcFormat } from "d3-time-format"
import { formatDate, formatDistance, formatPace } from "helpers/formatters"
import { bucketShares, clearSelection, getRuns, getTimes, periodsAbove, publish, runsInBuckets, subscribe } from "helpers/linked_selection"
import { observeSize } from "helpers/resize"
import { parseTime } from "helpers/time"
import { escapeHtml, hideTooltip, moveTooltip, showTooltip } from "helpers/tooltip"

const MARGIN = { top: 8, right: 8, bottom: 24, left: 44 }
const DAY_MS = 86400000

const METRICS = {
  distance: { weight: run => run.km, value: bucket => bucket.distance, text: value => `${formatDistance(value)} km` },
  elevation: { weight: run => run.elev, value: bucket => bucket.elevation, text: value => `${Math.round(value)} m` },
  avg_distance: { value: bucket => bucket.avg_distance, text: value => `${formatDistance(value)} km` },
  avg_pace: { value: bucket => (bucket.avg_pace ? 3600 / bucket.avg_pace : null), text: speed => `${formatPace(3600 / speed)} /km`, tick: speed => (speed > 0 ? formatPace(3600 / speed) : "") },
  avg_vdot: { value: bucket => bucket.avg_vdot, text: value => value.toFixed(1) }
}

const monthLabel = utcFormat("%b")
const monthYearLabel = utcFormat("%b %Y")

export default class extends Controller {
  static targets = ["chart"]
  static values = { data: Object, metric: { type: String, default: "distance" } }

  connect() {
    this.svg = select(this.chartTarget).append("svg").attr("class", "block")
    this.stopObserving = observeSize(this.chartTarget, size => {
      this.size = size
      this.draw()
    })
    this.unsubscribe = subscribe(selection => this.#apply(selection))
  }

  disconnect() {
    this.stopObserving()
    this.unsubscribe()
    this.svg.remove()
    hideTooltip()
    clearSelection()
  }

  #apply(selection) {
    const view = this.view
    if (!view) return
    const shares = selection ? bucketShares(getRuns(), view.starts, selection.runs, view.metric.weight || (() => 1)) : null

    if (Boolean(selection) !== view.active) {
      view.bars.attr("fill-opacity", selection ? 0.3 : null)
      view.active = Boolean(selection)
    }
    view.shareNodes.forEach((node, index) => {
      const height = Math.round((shares?.[index] ?? 0) * view.heights[index])
      if (height !== view.drawn[index]) {
        view.drawn[index] = height
        node.setAttribute("height", height)
        node.setAttribute("y", view.innerHeight - height)
      }
    })
  }

  metric(event) {
    this.metricValue = event.target.value
  }

  metricValueChanged() {
    if (this.size) this.draw()
  }

  draw() {
    const { width, height } = this.size
    const { granularity, buckets } = this.dataValue
    const metric = METRICS[this.metricValue]
    const values = buckets.map(metric.value)
    const innerWidth = width - MARGIN.left - MARGIN.right
    const innerHeight = height - MARGIN.top - MARGIN.bottom
    const x = scaleBand().domain(buckets.map((_, index) => index)).range([0, innerWidth]).padding(0.15)
    const y = scaleLinear().domain([0, max(values, value => value) || 1]).nice().range([innerHeight, 0])

    this.svg.attr("width", width).attr("height", height).selectAll("*").remove()
    const chart = this.svg.append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)

    const yAxis = chart.append("g").call(
      axisLeft(y)
        .ticks(5)
        .tickSize(-innerWidth)
        .tickFormat(metric.tick || y.tickFormat(5))
    )
    const xAxis = chart
      .append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(
        axisBottom(x)
          .tickValues(this.tickIndexes(buckets, granularity, x.step()))
          .tickFormat(index => this.tickLabel(buckets, index, granularity))
          .tickSize(4)
      )
    for (const axis of [xAxis, yAxis]) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }
    xAxis.selectAll("line").attr("stroke", "var(--chart-axis)")

    chart
      .append("g")
      .selectAll("rect")
      .data(buckets)
      .join("rect")
      .attr("x", (_, index) => x(index))
      .attr("width", x.bandwidth())
      .attr("y", (_, index) => (values[index] == null ? innerHeight : y(values[index])))
      .attr("height", (_, index) => (values[index] == null ? 0 : innerHeight - y(values[index])))
      .attr("rx", Math.min(2, x.bandwidth() / 2))
      .attr("fill", "var(--chart-accent)")
      .attr("class", "pointer-events-none")

    const bars = chart.selectAll("rect")
    const heights = values.map(value => (value == null ? 0 : innerHeight - y(value)))
    const shares = chart
      .append("g")
      .selectAll("rect")
      .data(buckets)
      .join("rect")
      .attr("x", (_, index) => x(index))
      .attr("width", x.bandwidth())
      .attr("y", innerHeight)
      .attr("height", 0)
      .attr("fill", "var(--chart-accent-highlight)")
      .attr("class", "pointer-events-none")
    this.view = { bars, shareNodes: shares.nodes(), drawn: heights.map(() => 0), active: false, heights, innerHeight, metric, starts: buckets.map(bucket => parseTime(bucket.from).getTime()) }
    chart
      .append("g")
      .selectAll("rect")
      .data(buckets)
      .join("rect")
      .attr("x", (_, index) => x(index) - x.step() * 0.075)
      .attr("width", x.step())
      .attr("height", innerHeight)
      .attr("fill", "transparent")
      .style("cursor", bucket => (bucket.href ? "pointer" : "default"))
      .on("mouseenter", (event, bucket) => {
        bars.filter((_, index) => index === buckets.indexOf(bucket)).attr("fill", "var(--chart-accent-highlight)")
        showTooltip(this.tooltip(bucket, granularity, metric), event)
      })
      .on("mousemove", event => {
        moveTooltip(event)
        const level = y.invert(pointer(event)[1])
        publish({ runs: new Set(runsInBuckets(getTimes(), this.view.starts, new Set(periodsAbove(values, level)))), span: null, source: "bars" })
      })
      .on("mouseleave", () => {
        bars.attr("fill", "var(--chart-accent)")
        hideTooltip()
        clearSelection()
      })
      .on("click", (_, bucket) => this.open(bucket))
  }

  tickIndexes(buckets, granularity, step) {
    const indexes = buckets.map((_, index) => index)
    if (granularity === "month") {
      return buckets.length <= 12 ? indexes : indexes.filter(index => parseTime(buckets[index].from).getUTCMonth() === 0)
    }
    if (granularity === "week") return indexes.filter(index => parseTime(buckets[index].from).getUTCDate() <= 7)
    return indexes.filter(index => step >= 16 || parseTime(buckets[index].from).getUTCDate() % 2 === 1)
  }

  tickLabel(buckets, index, granularity) {
    const date = parseTime(buckets[index].from)
    if (granularity === "day") return date.getUTCDate()
    if (granularity === "month" && buckets.length > 12) return date.getUTCFullYear()
    return monthLabel(date)
  }

  tooltip(bucket, granularity, metric) {
    const date = parseTime(bucket.from)
    const title = granularity === "month" ? monthYearLabel(date) : granularity === "week" ? `Week of ${formatDate(bucket.from)}` : formatDate(bucket.from)
    const value = metric.value(bucket)
    const text = value == null ? "–" : metric.text(value)
    return `<div class="font-medium">${escapeHtml(title)}</div><div>${escapeHtml(text)}</div><div class="text-zinc-500">${bucket.runs} ${bucket.runs === 1 ? "run" : "runs"}</div>`
  }

  open(bucket) {
    if (!bucket.href) return
    hideTooltip()
    window.Turbo.visit(bucket.href)
  }
}
