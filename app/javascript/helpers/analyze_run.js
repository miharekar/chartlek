export const METRICS = {
  km: run => run.km,
  pace: run => (run.pace > 0 ? 3600 / run.pace : null),
  hr: run => run.hr,
  vdot: run => run.vdot
}

export function histogram(runs, metric, count = 12) {
  const read = METRICS[metric]
  const values = runs.map(read)
  const known = values.filter(value => value != null)
  if (!known.length) return []

  const low = Math.min(...known)
  const high = Math.max(...known)
  const width = (high > low ? high - low : 1) / count
  const bins = Array.from({ length: count }, (_, index) => ({ x0: low + index * width, x1: low + (index + 1) * width, runs: [] }))
  values.forEach((value, index) => {
    if (value != null) bins[Math.min(count - 1, Math.floor((value - low) / width))].runs.push(index)
  })
  return bins
}

export function selectRuns(bins, [from, to]) {
  const selected = new Set()
  for (const bin of bins) {
    if (bin.x1 > from && bin.x0 < to) bin.runs.forEach(index => selected.add(index))
  }
  return selected
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

const DAY_MS = 86_400_000
const dayStart = time => Math.floor(time / DAY_MS) * DAY_MS

export function average(runs, metric) {
  const known = runs.map(METRICS[metric]).filter(value => value != null)
  return known.length ? known.reduce((sum, value) => sum + value, 0) / known.length : null
}

export function timelineTicks(from, to, race) {
  const window = Math.round((dayStart(to) - from) / DAY_MS)
  const ticks = []
  for (let days = window; days > 0; days -= 30) ticks.push({ t: dayStart(to) - days * DAY_MS, label: `${days} days before` })
  return [...ticks, { t: to, label: race ? "race day" : "run day" }]
}

export function daysBefore(currentTime, time) {
  return Math.round((dayStart(currentTime) - dayStart(time)) / DAY_MS)
}

export function sameDayRuns(runs, run) {
  return runs.filter(other => dayStart(other.t) === dayStart(run.t))
}
