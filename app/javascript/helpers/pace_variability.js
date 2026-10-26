import { formatDistanceRange, formatPace } from "helpers/formatters"

const BASE = 0.25
const FLOOR = 0.75

const sum = values => values.reduce((total, value) => total + value, 0)

export function variabilityWedges(bars) {
  const speeds = bars.map(bar => bar.distance / bar.time)
  const mean = speeds.length ? sum(speeds) / speeds.length : 0
  if (speeds.length < 2 || !(mean > 0)) return []

  const wedges = speeds.map((speed, index) => {
    const deviation = (speed - mean) / mean
    return { from: bars[index].from, to: bars[index].to, speed, deviation, value: Math.abs(deviation) + BASE }
  })
  const limit = Math.max(FLOOR, ...wedges.map(wedge => wedge.value))
  const step = (2 * Math.PI) / wedges.length
  return wedges.map((wedge, index) => ({ ...wedge, ratio: wedge.value / limit, start: index * step, end: (index + 1) * step }))
}

export function wedgeSummary(wedge) {
  const percent = wedge.deviation * 100
  const rows = [
    ["Pace", `${formatPace(1000 / wedge.speed)} /km`],
    ["Speed vs average", `${percent > 0 ? "+" : ""}${percent.toFixed(1)}%`]
  ]
  const title = formatDistanceRange(wedge.from, wedge.to)
  return { title, rows, label: [title, ...rows.map(([name, value]) => `${name} ${value}`)].join(". ") }
}

export function centreFontSize(text, hole) {
  return Math.min(hole * 0.62, (hole * 1.64) / (text.length * 0.6))
}
