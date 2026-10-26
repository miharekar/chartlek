import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { scaleLinear } from "d3-scale"
import { select } from "d3-selection"
import { formatDuration } from "helpers/formatters"
import { elevationBins, speedWindows } from "helpers/recording_bars"
import { observeSize } from "helpers/resize"
import { escapeHtml, hideTooltip, isTooltipFor, moveTooltip, showTooltipFor } from "helpers/tooltip"

const HEIGHT = 200
const MARGIN = { top: 22, right: 12, bottom: 30, left: 44 }

export default class extends Controller {
  static targets = ["chart"]
  static values = { samples: Array, kind: String, unit: { type: String, default: "bars" } }

  connect() {
    this.current = 0
    this.svg = select(this.chartTarget).append("svg").attr("class", "block").attr("role", "group")
    this.stopObserving = observeSize(this.chartTarget, ({ width }) => {
      this.width = width
      this.draw()
    })
  }

  disconnect() {
    this.stopObserving()
    this.dismiss()
    this.svg.remove()
  }

  unitValueChanged() {
    this.current = 0
    if (this.width) this.draw()
  }

  dismiss() {
    if (this.svg.selectAll("g.sample").nodes().some(isTooltipFor)) hideTooltip()
  }

  draw() {
    this.dismiss()
    this.svg.selectAll("*").remove()
    const speed = this.kindValue === "speed"
    const samples = speed ? speedWindows(this.samplesValue) : elevationBins(this.samplesValue, this.unitValue === "splits")
    if (!samples.length) return
    const bottom = HEIGHT - MARGIN.bottom
    const x = scaleLinear().domain([0, samples.at(-1).to]).range([MARGIN.left, this.width - MARGIN.right])
    const limit = Math.max(1, ...samples.flatMap(sample => [sample.up || 0, sample.down || 0]))
    const y = scaleLinear().domain([-limit, limit]).nice(4).range([bottom, MARGIN.top])
    this.svg.attr("width", this.width).attr("height", HEIGHT)
    const axes = [
      this.svg.append("g").attr("transform", `translate(0,${bottom})`).call(axisBottom(x).ticks(Math.max(2, Math.floor(this.width / 85))).tickFormat(value => speed ? formatDuration(value) : `${value} km`).tickSizeOuter(0)),
      this.svg.append("g").attr("transform", `translate(${MARGIN.left},0)`).call(axisLeft(y).ticks(4).tickFormat(value => `${value > 0 ? "+" : ""}${value}${speed ? "%" : ""}`).tickSizeOuter(0))
    ]
    for (const axis of axes) {
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line, path").attr("stroke", "var(--chart-grid)")
    }
    this.svg.append("text").attr("x", MARGIN.left).attr("y", 12).attr("font-size", 11).attr("fill", "var(--chart-axis)").text(speed ? "Speed vs average (%)" : "Gained / lost (m)")
    this.svg.append("line").attr("x1", MARGIN.left).attr("x2", this.width - MARGIN.right).attr("y1", y(0)).attr("y2", y(0)).attr("stroke", "var(--chart-axis)")
    const groups = this.svg.selectAll("g.sample").data(samples).join("g").attr("class", "sample").attr("tabindex", (_, index) => (index === Math.min(this.current, samples.length - 1) ? 0 : -1)).attr("role", "img").attr("aria-label", sample => sample.lines.join(". "))
    const barWidth = sample => (x(sample.to) - x(sample.from)) * 0.9
    groups.filter(sample => sample.up != null).append("rect").attr("x", sample => x(sample.from)).attr("width", barWidth)
      .attr("y", sample => y(sample.up)).attr("height", sample => Math.max(sample.up === 0 && sample.down === 0 ? 1 : 0, y(0) - y(sample.up))).attr("fill", "var(--chart-accent)")
    groups.filter(sample => sample.down != null).append("rect").attr("x", sample => x(sample.from)).attr("width", barWidth)
      .attr("y", y(0)).attr("height", sample => y(-sample.down) - y(0)).attr("fill", "var(--chart-highlight)")
    groups.append("rect").attr("class", "hit").attr("x", sample => x(sample.from)).attr("width", sample => x(sample.to) - x(sample.from))
      .attr("y", MARGIN.top).attr("height", bottom - MARGIN.top).attr("fill", "transparent")
    const show = (event, sample) => showTooltipFor(sample.lines.map(text => `<div>${escapeHtml(text)}</div>`).join(""), event.currentTarget)
    groups.on("mouseenter", (event, sample) => {
      show(event, sample)
      if (document.activeElement !== event.currentTarget) moveTooltip(event)
    }).on("mousemove", event => {
      if (isTooltipFor(event.currentTarget) && document.activeElement !== event.currentTarget) moveTooltip(event)
    }).on("mouseleave", event => {
      if (isTooltipFor(event.currentTarget) && document.activeElement !== event.currentTarget) hideTooltip()
    }).on("focus", (event, sample) => {
      this.#rove(groups, event.currentTarget)
      select(event.currentTarget).select(".hit").attr("stroke", "var(--chart-axis)").attr("stroke-width", 2)
      show(event, sample)
    }).on("blur", event => {
      select(event.currentTarget).select(".hit").attr("stroke", null)
      if (isTooltipFor(event.currentTarget)) hideTooltip()
    }).on("keydown", event => {
      if (event.key === "Escape" && isTooltipFor(event.currentTarget)) hideTooltip()
      else this.#move(event, groups.nodes())
    })
  }

  #rove(groups, focused) {
    this.current = groups.nodes().indexOf(focused)
    groups.attr("tabindex", (_, index) => (index === this.current ? 0 : -1))
  }

  #move(event, nodes) {
    const last = nodes.length - 1
    const target = { ArrowLeft: this.current - 1, ArrowRight: this.current + 1, Home: 0, End: last }[event.key]
    if (target == null) return
    event.preventDefault()
    nodes[Math.max(0, Math.min(last, target))].focus()
  }
}
