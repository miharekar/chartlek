import { Controller } from "@hotwired/stimulus"
import { arc } from "d3-shape"
import { select } from "d3-selection"
import { centreFontSize, variabilityWedges, wedgeSummary } from "helpers/pace_variability"
import { observeSize } from "helpers/resize"
import { rovingTarget } from "helpers/roving"
import { hideTooltip, isTooltipFor, moveTooltip, showTooltipFor, tooltipHtml } from "helpers/tooltip"

const MAX_SIZE = 280
const HOLE = 0.46

export default class extends Controller {
  static targets = ["chart"]
  static values = { bars: Array, percent: Number }

  connect() {
    this.current = 0
    this.wedges = variabilityWedges(this.barsValue)
    this.svg = select(this.chartTarget).append("svg").attr("class", "mx-auto block")
    this.stopObserving = observeSize(this.chartTarget, ({ width }) => {
      this.width = width
      this.draw()
    })
  }

  disconnect() {
    this.stopObserving()
    this.#dismiss()
    this.svg.remove()
  }

  draw() {
    this.#dismiss()
    this.svg.selectAll("*").remove()
    if (!this.wedges.length || !this.width) return

    const size = Math.min(this.width, MAX_SIZE)
    const outer = size / 2 - 2
    const inner = outer * HOLE
    const gap = this.wedges.length <= 90 ? 0.012 : 0
    const shape = arc().startAngle(wedge => wedge.start).endAngle(wedge => wedge.end).padAngle(gap).innerRadius(inner)
    const visible = wedge => shape.outerRadius(inner + (outer - inner) * wedge.ratio)(wedge)
    const sector = wedge => arc().startAngle(wedge.start).endAngle(wedge.end).innerRadius(inner).outerRadius(outer)()

    this.svg.attr("width", size).attr("height", size)
    const wheel = this.svg.append("g").attr("transform", `translate(${size / 2},${size / 2})`)
    const groups = wheel
      .selectAll("g.sample")
      .data(this.wedges)
      .join("g")
      .attr("class", "sample")
      .attr("tabindex", (_, index) => (index === Math.min(this.current, this.wedges.length - 1) ? 0 : -1))
      .attr("role", "img")
      .attr("aria-label", wedge => wedgeSummary(wedge).label)
    groups.append("path").attr("class", "fill").attr("d", visible).attr("fill", "var(--chart-accent)")
    groups.append("path").attr("class", "hit").attr("d", sector).attr("fill", "transparent")

    const percent = this.percentValue.toFixed(1)
    const text = wheel.append("text").attr("text-anchor", "middle").attr("dominant-baseline", "central").attr("fill", "currentColor").attr("font-weight", 600).attr("pointer-events", "none")
    text.attr("font-size", centreFontSize(`${percent}%`, inner)).text(percent)
    text.append("tspan").attr("font-size", "0.6em").attr("fill", "var(--chart-axis)").text("%")

    const show = (event, wedge) => {
      const { title, rows } = wedgeSummary(wedge)
      showTooltipFor(tooltipHtml(title, rows), event.currentTarget)
      select(event.currentTarget).select(".fill").attr("fill", "var(--chart-accent-highlight)")
    }
    const settle = node => select(node).select(".fill").attr("fill", "var(--chart-accent)")

    groups
      .on("mouseenter", (event, wedge) => {
        show(event, wedge)
        if (document.activeElement !== event.currentTarget) moveTooltip(event)
      })
      .on("mousemove", event => {
        if (isTooltipFor(event.currentTarget) && document.activeElement !== event.currentTarget) moveTooltip(event)
      })
      .on("mouseleave", event => {
        if (document.activeElement === event.currentTarget) return
        settle(event.currentTarget)
        if (isTooltipFor(event.currentTarget)) hideTooltip()
      })
      .on("focus", (event, wedge) => {
        this.#rove(groups, event.currentTarget)
        select(event.currentTarget).select(".hit").attr("stroke", "var(--chart-axis)").attr("stroke-width", 2)
        show(event, wedge)
      })
      .on("blur", event => {
        settle(event.currentTarget)
        select(event.currentTarget).select(".hit").attr("stroke", null)
        if (isTooltipFor(event.currentTarget)) hideTooltip()
      })
      .on("keydown", event => {
        if (event.key === "Escape" && isTooltipFor(event.currentTarget)) return hideTooltip()
        const target = rovingTarget(event.key, this.current, this.wedges.length - 1)
        if (target == null) return
        event.preventDefault()
        groups.nodes()[target].focus()
      })
  }

  #rove(groups, focused) {
    this.current = groups.nodes().indexOf(focused)
    groups.attr("tabindex", (_, index) => (index === this.current ? 0 : -1))
  }

  #dismiss() {
    if (this.svg.selectAll("g.sample").nodes().some(isTooltipFor)) hideTooltip()
  }
}
