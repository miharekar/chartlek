import { Controller } from "@hotwired/stimulus"
import { create, select } from "d3-selection"
import { cellSelected, clearSelection, dayStart, getTimes, keysOf, levelKeys, publish, runsInKeys, spanSelection, subscribe, weekStart } from "helpers/linked_selection"
import { observeSize } from "helpers/resize"
import { scrub } from "helpers/scrub"
import { escapeHtml, hideTooltip, moveTooltip, showTooltip } from "helpers/tooltip"

const GAP = 2
const LABEL_WIDTH = 40
const LABEL_HEIGHT = 18
const LEGEND_HEIGHT = 56
const MAX_CELL = 48
const DAY_MS = 86400000
const DIMMED = 0.2

const FILLS = [
  ["var(--chart-grid)", 0.7],
  ["var(--chart-accent-low)", 1],
  ["var(--chart-accent)", 0.5],
  ["var(--chart-accent)", 1],
  ["var(--chart-accent-highlight)", 1],
  ["var(--chart-accent-highlight)", 1],
  ["var(--chart-accent-highlight)", 1]
]

export default class extends Controller {
  static targets = ["chart"]
  static values = { data: Object }

  connect() {
    this.svg = select(this.chartTarget).append("svg").attr("class", "block")
    this.stopObserving = observeSize(this.chartTarget, ({ width }) => {
      if (width === this.width) return
      this.width = width
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

  #keyOf() {
    return this.step === 7 ? weekStart : dayStart
  }

  #apply(selection) {
    if (!this.groups) return
    const ignore = !selection || selection.source === "cell"

    const keys = ignore || selection.span ? null : keysOf(getTimes(), selection.runs, this.#keyOf())

    this.nodes.forEach((node, index) => {
      const dim = !ignore && !cellSelected(this.cells[index], this.step, selection.span, keys)
      if (dim !== this.dimmed[index]) {
        this.dimmed[index] = dim
        if (dim) node.setAttribute("opacity", DIMMED)
        else node.removeAttribute("opacity")
      }
    })
  }

  draw() {
    const { rows, cols, columns, cells, step, thresholds, unit } = this.dataValue
    this.cells = cells
    this.step = step
    const cell = Math.max(6, Math.min(MAX_CELL, Math.floor((this.width - LABEL_WIDTH) / cols)))
    const gridHeight = rows.length * cell

    this.svg
      .attr("width", this.width)
      .attr("height", LABEL_HEIGHT + gridHeight + LABEL_HEIGHT + LEGEND_HEIGHT)
      .selectAll("*")
      .remove()
    const chart = this.svg.append("g").attr("transform", `translate(${LABEL_WIDTH},${LABEL_HEIGHT})`)

    const labelStyle = selection => selection.attr("fill", "var(--chart-axis)").attr("font-size", 11)
    labelStyle(
      chart
        .selectAll("text.row")
        .data(rows)
        .join("text")
        .attr("x", -8)
        .attr("y", (_, index) => index * cell + cell / 2)
        .attr("text-anchor", "end")
        .attr("dominant-baseline", "central")
        .text(label => label)
    )
    labelStyle(
      chart
        .selectAll("text.column")
        .data(columns)
        .join("text")
        .attr("x", column => column.col * cell)
        .attr("y", -6)
        .text(column => column.label)
    )

    const layer = create("svg:g")
    const groups = layer
      .selectAll("g.cell")
      .data(cells)
      .join("g")
      .attr("transform", cellData => `translate(${cellData.col * cell},${cellData.row * cell})`)
      .style("cursor", cellData => (cellData.href ? "pointer" : "default"))
      .on("click", (_, cellData) => this.open(cellData))

    groups
      .append("rect")
      .attr("width", cell - GAP)
      .attr("height", cell - GAP)
      .attr("rx", Math.min(3, cell / 5))
      .attr("fill", cellData => FILLS[cellData.level][0])
      .attr("fill-opacity", cellData => FILLS[cellData.level][1])
    groups.filter(cellData => cellData.text && cell >= 24).append("text").attr("x", 4).attr("y", 12).attr("font-size", 10).attr("pointer-events", "none").attr("fill", cellData => (cellData.level >= 3 ? "var(--chart-grid)" : "var(--chart-axis)")).text(cellData => cellData.text)
    this.decorate(groups.filter(cellData => cellData.level >= 5), cell - GAP)
    chart.append(() => layer.node())

    scrub(groups, {
      mode: "items",
      enter: (event, cellData) => {
        showTooltip(cellData.tip.map((line, index) => `<div class="${index === 0 ? "font-medium" : ""}">${escapeHtml(line)}</div>`).join(""), event)
        publish(spanSelection(getTimes(), cellData.from, cellData.from + this.step * DAY_MS, "cell"))
      },
      move: moveTooltip,
      leave: () => {
        hideTooltip()
        clearSelection()
      }
    })

    this.groups = groups
    this.nodes = groups.nodes()
    this.dimmed = this.nodes.map(() => false)

    this.drawLegend(thresholds, unit, LABEL_HEIGHT + gridHeight + LABEL_HEIGHT)
  }

  decorate(selection, size) {
    selection
      .append("circle")
      .attr("cx", size / 2)
      .attr("cy", size / 2)
      .attr("r", size * 0.3)
      .attr("fill", "none")
      .attr("stroke", "var(--chart-grid)")
      .attr("stroke-width", Math.max(1, size / 10))
      .attr("pointer-events", "none")
    selection
      .filter(cellData => cellData.level >= 6)
      .append("circle")
      .attr("cx", size / 2)
      .attr("cy", size / 2)
      .attr("r", size * 0.1)
      .attr("fill", "var(--chart-grid)")
      .attr("pointer-events", "none")
  }

  drawLegend(thresholds, unit, top) {
    const swatch = 14
    const itemWidth = 56
    const legend = this.svg.append("g").attr("transform", `translate(${this.width - thresholds.length * itemWidth},${top + 8})`)
    const items = legend
      .selectAll("g")
      .data(thresholds.map((threshold, index) => ({ threshold, level: index + 1 })))
      .join("g")
      .attr("transform", (_, index) => `translate(${index * itemWidth},0)`)

    scrub(items, {
      mode: "items",
      enter: (_, item) => publish({ runs: new Set(runsInKeys(getTimes(), this.#keyOf(), levelKeys(this.cells, item.level))), span: null, source: "legend" }),
      leave: () => clearSelection()
    })
    items.append("text").attr("y", swatch / 2).attr("dominant-baseline", "central").attr("font-size", 11).attr("fill", "var(--chart-axis)").text(item => `>${item.threshold}`)
    items
      .append("rect")
      .attr("x", 30)
      .attr("width", swatch)
      .attr("height", swatch)
      .attr("rx", 3)
      .attr("fill", item => FILLS[item.level][0])
      .attr("fill-opacity", item => FILLS[item.level][1])
    const marks = items.append("g").attr("transform", "translate(30,0)")
    this.decorate(marks.filter(item => item.level >= 5), swatch)
    legend.append("text").attr("x", thresholds.length * itemWidth).attr("y", 32).attr("text-anchor", "end").attr("font-size", 11).attr("fill", "var(--chart-axis)").text(unit)
  }

  open(cellData) {
    if (!cellData.href) return
    hideTooltip()
    window.Turbo.visit(cellData.href)
  }
}
