import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { brushX } from "d3-brush"
import { max } from "d3-array"
import { scaleLinear, scaleUtc } from "d3-scale"
import { select } from "d3-selection"
import { formatDate, formatDistance, formatDuration, formatPace } from "helpers/formatters"
import { histogram, selectRuns, summarize } from "helpers/analyze_run"
import { observeSize } from "helpers/resize"
import { parseTime } from "helpers/time"
import { hideTooltip, moveTooltip, showTooltip, tooltipHtml } from "helpers/tooltip"

const MARGIN = { top: 8, right: 12, bottom: 24, left: 36 }
const HISTOGRAM_HEIGHT = 176
const HISTOGRAM_TOP = 12
const TIMELINE_HEIGHT = 112

const LABELS = { km: "km", pace: "/km", hr: "bpm", vdot: "VDOT" }

export default class extends Controller {
  static targets = ["histogram", "timeline", "summary"]
  static values = { runs: Array, from: Number, to: Number, metric: { type: String, default: "km" } }

  connect() {
    this.histogramSvg = select(this.histogramTarget).append("svg").attr("class", "block w-full").attr("height", HISTOGRAM_HEIGHT)
    this.timelineSvg = select(this.timelineTarget).append("svg").attr("class", "block w-full").attr("height", TIMELINE_HEIGHT)
    this.stopObserving = observeSize(this.histogramTarget, ({ width }) => {
      this.width = width
      this.draw()
    })
  }

  disconnect() {
    this.stopObserving()
    this.histogramSvg.remove()
    this.timelineSvg.remove()
    hideTooltip()
  }

  metric(event) {
    this.metricValue = event.target.value
  }

  metricValueChanged() {
    if (this.width) this.draw()
  }

  draw() {
    this.selected = null
    this.bins = histogram(this.runsValue, this.metricValue)
    this.drawHistogram()
    this.drawTimeline()
    this.renderSummary()
  }

  drawHistogram() {
    const metric = this.metricValue
    const { width, bins } = this
    const flipped = metric === "pace"
    const domain = bins.length ? [bins[0].x0, bins[bins.length - 1].x1] : [0, 1]
    const x = scaleLinear()
      .domain(flipped ? [domain[1], domain[0]] : domain)
      .range([MARGIN.left, width - MARGIN.right])
    const y = scaleLinear()
      .domain([0, max(bins, bin => bin.runs.length) || 1])
      .nice()
      .range([HISTOGRAM_HEIGHT - MARGIN.bottom, HISTOGRAM_TOP])
    const svg = this.histogramSvg.attr("width", width)
    svg.selectAll("*").remove()

    svg
      .append("g")
      .attr("fill", "var(--chart-accent)")
      .selectAll("rect")
      .data(bins)
      .join("rect")
      .attr("x", bin => Math.min(x(bin.x0), x(bin.x1)) + 0.5)
      .attr("width", bin => Math.max(1, Math.abs(x(bin.x1) - x(bin.x0)) - 1))
      .attr("y", bin => y(bin.runs.length))
      .attr("height", bin => y(0) - y(bin.runs.length))

    const xAxis = svg
      .append("g")
      .attr("transform", `translate(0,${HISTOGRAM_HEIGHT - MARGIN.bottom})`)
      .call(
        axisBottom(x)
          .ticks(Math.max(2, Math.floor(width / 80)))
          .tickFormat(value => (flipped ? formatPace(3600 / value) : value))
          .tickSizeOuter(0)
      )
    const yAxis = svg
      .append("g")
      .attr("transform", `translate(${MARGIN.left},0)`)
      .call(axisLeft(y).ticks(4).tickSize(-(width - MARGIN.left - MARGIN.right)).tickFormat(value => (Number.isInteger(value) ? value : "")).tickSizeOuter(0))
    for (const axis of [xAxis, yAxis]) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }
    svg.append("text").attr("fill", "var(--chart-axis)").attr("font-size", 11).attr("x", MARGIN.left).attr("y", 9).text(LABELS[metric])

    if (!bins.length) return
    const brush = brushX()
      .extent([
        [MARGIN.left, HISTOGRAM_TOP],
        [width - MARGIN.right, HISTOGRAM_HEIGHT - MARGIN.bottom]
      ])
      .on("brush end", event => {
        if (!event.selection) this.selected = null
        else this.selected = selectRuns(this.bins, event.selection.map(x.invert).sort((a, b) => a - b))
        this.drawTimeline()
        this.renderSummary()
      })
    const group = svg.append("g").call(brush)
    group.select(".selection").attr("fill", "var(--chart-accent-highlight)").attr("fill-opacity", 0.25).attr("stroke", "var(--chart-accent-highlight)")
  }

  drawTimeline() {
    const { width } = this
    const x = scaleUtc()
      .domain([this.fromValue, this.toValue])
      .range([MARGIN.left, width - MARGIN.right])
    const y = scaleLinear()
      .domain([0, max(this.runsValue, run => run.km) || 1])
      .range([TIMELINE_HEIGHT - MARGIN.bottom, MARGIN.top])
    const svg = this.timelineSvg.attr("width", width)
    svg.selectAll("*").remove()

    const axis = svg
      .append("g")
      .attr("transform", `translate(0,${TIMELINE_HEIGHT - MARGIN.bottom})`)
      .call(
        axisBottom(x)
          .ticks(Math.max(2, Math.floor(width / 90)))
          .tickSizeOuter(0)
      )
    axis.select(".domain").attr("stroke", "var(--chart-grid)")
    axis.selectAll(".tick line").attr("stroke", "var(--chart-grid)")
    axis.selectAll("text").attr("fill", "var(--chart-axis)")

    const fill = (_, index) => (!this.selected ? "var(--chart-accent)" : this.selected.has(index) ? "var(--chart-highlight)" : "var(--chart-muted)")
    svg
      .append("g")
      .selectAll("rect")
      .data(this.runsValue)
      .join("rect")
      .attr("x", run => x(parseTime(run.t)) - 1.5)
      .attr("width", 3)
      .attr("y", run => y(run.km))
      .attr("height", run => y(0) - y(run.km))
      .attr("fill", fill)
      .attr("fill-opacity", (_, index) => (!this.selected || this.selected.has(index) ? 1 : 0.5))
      .style("cursor", "pointer")
      .on("mousemove", (event, run) => {
        showTooltip(this.tooltipHtml(run), event)
        moveTooltip(event)
      })
      .on("mouseleave", hideTooltip)
      .on("click", (_, run) => window.Turbo.visit(run.url))
  }

  renderSummary() {
    const runs = this.runsValue
    const all = new Set(runs.map((_, index) => index))
    const { count, km, seconds, share } = summarize(runs, this.selected || all)
    const scope = this.selected ? "Selected" : "All"
    this.summaryTarget.innerHTML = `${scope}: <strong>${count}</strong> ${count === 1 ? "run" : "runs"} · <strong>${formatDistance(km)} km</strong> · <strong>${formatDuration(seconds)}</strong> · <strong>${share.toFixed(0)}%</strong> of training distance`
  }

  tooltipHtml(run) {
    return tooltipHtml(formatDate(run.t), [
      ["Distance", `${formatDistance(run.km)} km`],
      ["Pace", `${formatPace(run.pace)} /km`],
      ["Time", formatDuration(run.s)],
      ["HR", run.hr == null ? "–" : run.hr],
      ["VDOT", run.vdot == null ? "–" : run.vdot.toFixed(1)]
    ])
  }
}
