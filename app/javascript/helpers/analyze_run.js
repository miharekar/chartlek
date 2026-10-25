export const METRICS = {
  km: run => run.km,
  pace: run => (run.pace > 0 ? 3600 / run.pace : null),
  hr: run => run.hr,
  spi: run => run.spi
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
