import { formatDistance, formatPace } from "helpers/formatters"

export const DAY_MS = 86_400_000
export const READOUTS = ["share", "hours", "distance", "count"]

export const METRICS = {
  km: run => run.km,
  pace: run => (run.pace > 0 ? 3600 / run.pace : null),
  vdot: run => run.vdot,
  hr: run => (run.hr > 0 ? run.hr : null)
}

export const dayStart = time => Math.floor(time / DAY_MS) * DAY_MS

export function niceTicks(low, high, count = 7) {
  const rough = (high - low) / count
  if (!(rough > 0)) return [low]
  const power = 10 ** Math.floor(Math.log10(rough))
  const step = [1, 2, 5, 10].map(factor => factor * power).find(candidate => candidate >= rough)
  const ticks = []
  for (let tick = Math.ceil(low / step) * step; tick <= high + step * 1e-9; tick += step) ticks.push(Number((Math.round(tick / step) * step).toPrecision(12)))
  return ticks
}

export function axis(metric, runs, current) {
  const values = [...runs, current].map(METRICS[metric]).filter(value => value != null)
  if (!values.length) return { domain: [0, 1], ticks: [0, 1] }

  const low = Math.min(...values)
  const high = Math.max(...values)
  const domain = {
    km: [0, Math.ceil(high) + 1],
    pace: [Math.min(4, Math.floor(low)), high + 1],
    vdot: [low - 1, high + 1],
    hr: low === high ? [low - 5, high + 5] : [Math.floor(low / 10) * 10, Math.ceil(high / 10) * 10]
  }[metric]
  return { domain, ticks: niceTicks(...domain) }
}

export function formatValue(metric, value, precise = false) {
  if (metric === "pace") return formatPace(3600 / value)
  if (metric === "km") return precise ? formatDistance(value) : String(Number(value.toFixed(1)))
  if (metric === "vdot") return precise ? value.toFixed(1) : String(Number(value.toFixed(1)))
  return String(Math.round(value))
}

export function edgeLabelPositions([from, to], width, reserve = 36) {
  const left = Math.min(Math.max(from, reserve), width - 2 * reserve)
  return [left, Math.min(Math.max(to, left), width - reserve)]
}

export function average(runs, metric) {
  const known = runs.map(METRICS[metric]).filter(value => value != null)
  return known.length ? known.reduce((sum, value) => sum + value, 0) / known.length : null
}

export function brushSelection(runs, metric, [low, high]) {
  const selected = new Set()
  runs.forEach((run, index) => {
    const value = METRICS[metric](run)
    if (value != null && value >= low && value <= high) selected.add(index)
  })
  return selected
}

export function valueOrder(runs, metric) {
  return runs
    .map((run, index) => ({ index, value: METRICS[metric](run) }))
    .filter(({ value }) => value != null)
    .sort((a, b) => a.value - b.value || a.index - b.index)
    .map(({ index }) => index)
}

export function summarize(runs, selected) {
  const chosen = runs.filter((_, index) => selected.has(index))
  const total = runs.reduce((sum, run) => sum + run.km, 0)
  const km = chosen.reduce((sum, run) => sum + run.km, 0)
  return {
    count: chosen.length,
    km,
    seconds: chosen.reduce((sum, run) => sum + run.s, 0),
    share: total > 0 ? (km / total) * 100 : 0
  }
}

export function nextReadout(mode) {
  return READOUTS[(READOUTS.indexOf(mode) + 1) % READOUTS.length]
}

export function readoutText(runs, selected, mode) {
  const { count, km, seconds } = summarize(runs, selected)
  if (mode === "share") return `${runs.length ? Math.round((count / runs.length) * 100) : 0}%`
  if (mode === "hours") return `${(seconds / 3600).toFixed(1)} h`
  if (mode === "distance") return `${formatDistance(km)} km`
  return `${count} ${count === 1 ? "run" : "runs"}`
}

export function timelineTicks(from, to, race) {
  const window = Math.round((dayStart(to) - from) / DAY_MS)
  const ticks = []
  for (let days = window; days > 0; days -= 30) ticks.push({ t: dayStart(to) - days * DAY_MS, label: `${days} days before` })
  return [...ticks, { t: dayStart(to), label: race ? "race day" : "run day" }]
}

export function daysBefore(currentTime, time) {
  return Math.round((dayStart(currentTime) - dayStart(time)) / DAY_MS)
}

export function dayLabel(currentTime, time, race) {
  const days = daysBefore(currentTime, time)
  if (days === 0) return race ? "race day" : "run day"
  return days === 1 ? "yesterday" : `${days} days before`
}

export function groupDays(runs) {
  const days = new Map()
  runs.forEach((run, index) => {
    const day = dayStart(run.t)
    if (!days.has(day)) days.set(day, [])
    days.get(day).push(index)
  })
  return [...days].sort((a, b) => a[0] - b[0]).map(([day, indexes]) => ({ day, indexes }))
}

export function lit(indexes, selected) {
  return selected ? indexes.filter(index => selected.has(index)) : indexes
}
