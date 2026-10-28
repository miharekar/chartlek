import { formatDistance, formatDuration, formatPace } from "helpers/formatters"
import { scrub } from "helpers/scrub"
import { hideTooltip, moveTooltip, showTooltip, tooltipHtml } from "helpers/tooltip"

const NAMES = { warmup: "Warm-up", active: "Active", recovery: "Recovery", rest: "Rest", cooldown: "Cool-down" }

export const STRIP_HEIGHT = 6
export const STRIP_SPACE = 17
const HIT_ABOVE = 6

export function labelled(steps) {
  const totals = {}
  for (const step of steps) totals[step.type] = (totals[step.type] || 0) + 1
  const seen = {}
  return steps.map(step => {
    const number = (seen[step.type] = (seen[step.type] || 0) + 1)
    const name = NAMES[step.type] || step.type
    return { ...step, label: totals[step.type] > 1 ? `${name} ${number} of ${totals[step.type]}` : name }
  })
}

export function stepAt(steps, meters) {
  const index = steps.findIndex((step, position) => meters >= step.from && (meters < step.to || (position === steps.length - 1 && meters <= step.to)))
  return index < 0 ? null : steps[index]
}

export function stepPace(step) {
  return step.to > step.from ? (step.time / (step.to - step.from)) * 1000 : null
}

export function stepRows(step) {
  const pace = stepPace(step)
  return [
    ["Distance", `${formatDistance((step.to - step.from) / 1000)} km`],
    ["Time", formatDuration(step.time)],
    pace != null && ["Pace", `${formatPace(pace)} /km`]
  ]
}

export function drawSteps(chart, steps, x, { innerHeight, tint = true, dividers = false }) {
  const stripTop = -STRIP_SPACE
  const left = step => x(step.from / 1000)
  const width = step => Math.max(1, x(step.to / 1000) - x(step.from / 1000))

  if (tint) {
    chart.insert("g", ":first-child").attr("pointer-events", "none")
      .selectAll("rect").data(steps.filter(step => step.type === "active")).join("rect")
      .attr("x", left).attr("width", width).attr("y", 0).attr("height", innerHeight)
      .attr("fill", "var(--step-active)").attr("fill-opacity", 0.1)
  }

  if (dividers) {
    chart.append("g").attr("pointer-events", "none").attr("stroke", "var(--chart-axis)").attr("stroke-opacity", 0.5).attr("stroke-width", 1)
      .selectAll("line").data(steps.slice(1)).join("line")
      .attr("x1", left).attr("x2", left).attr("y1", 0).attr("y2", innerHeight)
  }

  const strip = chart.append("g")
  strip.selectAll("rect.step").data(steps).join("rect").attr("class", "step").attr("pointer-events", "none")
    .attr("x", left).attr("width", step => Math.max(1, width(step) - 1)).attr("y", stripTop).attr("height", STRIP_HEIGHT).attr("rx", 1.5)
    .attr("fill", step => `var(--step-${step.type})`)
  const hits = strip.selectAll("rect.hit").data(steps).join("rect").attr("class", "hit").attr("fill", "transparent")
    .attr("x", left).attr("width", width).attr("y", stripTop - HIT_ABOVE).attr("height", HIT_ABOVE + STRIP_HEIGHT + 2)
  const show = (event, step) => {
    showTooltip(tooltipHtml(step.label, stepRows(step)), event)
    moveTooltip(event)
  }
  scrub(hits, { mode: "items", enter: show, move: show, leave: hideTooltip })
}
