import { Controller } from "@hotwired/stimulus"
import { axisBottom, axisLeft } from "d3-axis"
import { extent, max } from "d3-array"
import { Delaunay } from "d3-delaunay"
import { scaleLinear } from "d3-scale"
import { pointer, select } from "d3-selection"
import { formatDate, formatDistance, formatPace } from "helpers/formatters"
import { paceScale } from "helpers/pace_scale"
import { clearRuns, clearSelection, hoverSelection, publish, selectionMean, setRuns, subscribe } from "helpers/linked_selection"
import { observeSize } from "helpers/resize"
import { scrub } from "helpers/scrub"
import { hideTooltip, moveTooltip, showTooltip, tooltipHtml } from "helpers/tooltip"

const MARGIN = { top: 8, right: 12, bottom: 24, left: 44 }
const PACE_TICKS = [180, 240, 300, 360, 450, 600, 900, 1800]
const HIT_RADIUS = 14
const STATES = {
  normal: ["var(--chart-accent)", 0.5],
  selected: ["var(--chart-highlight)", 1],
  dim: ["var(--chart-muted)", 0.3]
}
const RADIUS = { normal: 2.5, selected: 3.5, dim: 2.5 }

function paint(node, state) {
  if (!node) return
  const [fill, opacity] = STATES[state]
  node.setAttribute("fill", fill)
  node.setAttribute("fill-opacity", opacity)
  node.setAttribute("r", RADIUS[state])
}

function raise(node) {
  node?.parentNode.appendChild(node)
}

const METRICS = {
  pace: { value: run => run.pace },
  hr: { value: run => run.hr },
  vdot: { value: run => run.vdot }
}

export default class extends Controller {
  static targets = ["chart", "metric", "title"]
  static values = { data: Object, metric: { type: String, default: "pace" } }

  connect() {
    this.runs = this.dataValue.runs
    setRuns(this.runs)
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
    clearRuns(this.runs)
    this.svg.remove()
    hideTooltip()
    clearSelection()
  }

  #apply(selection) {
    const view = this.view
    if (!view) return
    const next = selection?.runs ?? null
    const previous = this.active

    if ((next == null) !== (previous == null)) {
      view.byRun.forEach((node, index) => paint(node, next ? (next.has(index) ? "selected" : "dim") : "normal"))
      if (next) for (const index of next) raise(view.byRun.get(index))
    } else if (next) {
      for (const index of next) {
        if (previous.has(index)) continue
        paint(view.byRun.get(index), "selected")
        raise(view.byRun.get(index))
      }
      for (const index of previous) if (!next.has(index)) paint(view.byRun.get(index), "dim")
    }
    this.active = next
    view.lastDot?.attr("display", next ? "none" : null)

    if (view.ring) {
      view.ring.attr("stroke-width", next ? 3 : 2)
      const mean = next && selectionMean(this.runs, next, view.key)
      const base = view.average[view.key]
      view.ring.attr("cx", view.x(mean ? mean.km : base.km)).attr("cy", view.y(mean ? mean.value : base.value))
    }
  }

  metric(event) {
    this.metricValue = event.currentTarget.value
  }

  metricValueChanged() {
    const pressed = this.metricTargets.find(button => button.value === this.metricValue)
    this.metricTargets.forEach(button => button.setAttribute("aria-pressed", button === pressed))
    this.titleTarget.textContent = `${pressed.textContent.trim()} vs distance`
    if (this.size) this.draw()
  }

  draw() {
    const { width, height } = this.size
    const { runs, last, average } = this.dataValue
    const key = this.metricValue
    const value = METRICS[key].value
    const innerWidth = width - MARGIN.left - MARGIN.right
    const innerHeight = height - MARGIN.top - MARGIN.bottom
    const shown = runs.map((run, index) => ({ run, index })).filter(({ run }) => value(run) != null)
    const x = scaleLinear()
      .domain([0, max(runs, run => run.km) || 1])
      .nice()
      .range([0, innerWidth])
    const y = this.yScale(key, shown.map(({ run }) => value(run)), innerHeight)
    const position = run => [x(run.km), Math.max(0, Math.min(innerHeight, y(value(run))))]

    this.svg.attr("width", width).attr("height", height).selectAll("*").remove()
    const chart = this.svg.append("g").attr("transform", `translate(${MARGIN.left},${MARGIN.top})`)

    const yAxis = chart.append("g").call(this.yAxis(key, y).tickSize(-innerWidth))
    const xAxis = chart
      .append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(axisBottom(x).ticks(Math.max(2, Math.floor(innerWidth / 60))).tickSizeOuter(0))
    for (const axis of [xAxis, yAxis]) {
      axis.select(".domain").remove()
      axis.selectAll("text").attr("fill", "var(--chart-axis)")
      axis.selectAll("line").attr("stroke", "var(--chart-grid)")
    }

    const points = shown.map(({ run }) => position(run))
    const dots = chart
      .append("g")
      .selectAll("circle")
      .data(points)
      .join("circle")
      .attr("cx", point => point[0])
      .attr("cy", point => point[1])
      .attr("r", 2.5)
      .attr("fill", "var(--chart-accent)")
      .attr("fill-opacity", 0.5)

    const lastRun = runs[last]
    let lastDot
    if (value(lastRun) != null) {
      const [lastX, lastY] = position(lastRun)
      lastDot = chart.append("circle").attr("cx", lastX).attr("cy", lastY).attr("r", 4.5).attr("fill", "var(--chart-highlight)")
    }
    let ring
    if (average[key]) {
      ring = chart
        .append("circle")
        .attr("cx", x(average[key].km))
        .attr("cy", y(average[key].value))
        .attr("r", 7)
        .attr("fill", "none")
        .attr("stroke", "var(--chart-accent-highlight)")
        .attr("stroke-width", 2)
    }

    const nodes = dots.nodes()
    this.view = { key, x, y, average, ring, lastDot, byRun: new Map(shown.map(({ index }, position) => [index, nodes[position]])) }
    this.active = null
    this.addHover(chart, shown, points, innerWidth, innerHeight)
  }

  yScale(key, values, innerHeight) {
    if (key === "pace") {
      const [fastest, slowest] = extent(values)
      const top = Math.max(150, fastest - 15)
      return paceScale([top, Math.max(Math.min(1800, slowest), top + 120)], [0, innerHeight])
    }
    const [low, high] = extent(values)
    return scaleLinear()
      .domain([low ?? 0, high ?? 1])
      .nice()
      .range([innerHeight, 0])
  }

  yAxis(key, y) {
    if (key === "pace") {
      const [fastest, slowest] = y.domain()
      return axisLeft(y).tickValues(PACE_TICKS.filter(pace => pace >= fastest && pace <= slowest))
    }
    return axisLeft(y).ticks(5)
  }

  addHover(chart, shown, points, innerWidth, innerHeight) {
    const delaunay = Delaunay.from(points)
    const quadrantPoints = shown.map(({ index }, position) => ({ x: points[position][0], y: points[position][1], index }))
    const ring = chart.append("circle").attr("r", 6).attr("fill", "none").attr("stroke", "var(--chart-axis)").attr("stroke-width", 1.5).attr("display", "none").attr("pointer-events", "none")
    let current

    chart
      .append("rect")
      .attr("x", -MARGIN.left)
      .attr("y", -MARGIN.top)
      .attr("width", innerWidth + MARGIN.left + MARGIN.right)
      .attr("height", innerHeight + MARGIN.top + MARGIN.bottom)
      .attr("fill", "transparent")
      .call(scrub, {
        move: event => {
          const [mouseX, mouseY] = pointer(event)
          const inPlot = mouseX >= 0 && mouseX <= innerWidth && mouseY >= 0 && mouseY <= innerHeight
          const found = inPlot && points.length ? delaunay.find(mouseX, mouseY) : -1
          const near = found >= 0 && Math.hypot(points[found][0] - mouseX, points[found][1] - mouseY) <= HIT_RADIUS
          publish({ runs: new Set(hoverSelection(quadrantPoints, mouseX, mouseY, innerWidth, innerHeight)), span: null, source: "scatter" })
          current = near ? shown[found].run : null
          event.currentTarget.style.cursor = near ? "pointer" : "default"

          if (near) {
            ring.attr("display", null).attr("cx", points[found][0]).attr("cy", points[found][1])
            showTooltip(this.tooltip(current), event)
          } else {
            ring.attr("display", "none")
            hideTooltip()
          }
        },
        leave: () => {
          ring.attr("display", "none")
          hideTooltip()
          clearSelection()
        }
      })
      .on("click", () => {
        if (current) window.Turbo.visit(current.href)
      })
  }

  tooltip(run) {
    const hr = run.hr == null ? "–" : `${run.hr} bpm`
    const vdot = run.vdot == null ? "–" : run.vdot.toFixed(1)
    return tooltipHtml(formatDate(run.t), [["Distance", `${formatDistance(run.km)} km`], ["Pace", `${formatPace(run.pace)} /km`], ["HR", hr], ["VDOT", vdot]], { heading: run.name || "Run" })
  }
}
