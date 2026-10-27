export const WEEK_MS = 604800000

export function weekIndex(start, ms) {
  return Math.floor((ms - start) / WEEK_MS)
}

export function weekTotals(category, count) {
  const totals = new Array(count).fill(0)
  for (const values of Object.values(category.bands)) for (let index = 0; index < count; index++) totals[index] += values[index]
  return totals
}

export function visibleBands(category, hidden) {
  const shown = new Set(category.groups.flatMap((group, index) => (hidden.has(index) ? [] : group.bands)))
  return Object.keys(category.bands).map(Number).filter(band => shown.has(band))
}

export function stackBands(category, bands, totals, percent) {
  let lower = new Array(totals.length).fill(0)
  const layers = bands.map(band => {
    const values = category.bands[band]
    const upper = lower.map((base, index) => base + (percent ? (totals[index] ? (values[index] / totals[index]) * 100 : 0) : values[index] / 3600))
    const layer = { band, lower, upper }
    lower = upper
    return layer
  })
  return { layers, top: lower }
}

export function peak(top, from, to) {
  let high = 0
  for (let index = Math.max(0, from); index < Math.min(top.length, to); index++) if (top[index] > high) high = top[index]
  return high
}

export function groupRows(category, week, hidden, totals) {
  return category.groups.flatMap((group, index) => {
    const seconds = group.bands.reduce((sum, band) => sum + (category.bands[band]?.[week] ?? 0), 0)
    return hidden.has(index) || seconds === 0 ? [] : [{ label: group.label, seconds, share: (seconds / totals[week]) * 100 }]
  })
}
