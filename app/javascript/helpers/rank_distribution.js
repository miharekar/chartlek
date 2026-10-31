const TRIM = 0.02

export function distribution(values, current) {
  if (!values.length) return []
  const sorted = [...values].sort((a, b) => a - b)
  const cut = Math.round(TRIM * (sorted.length - 1))
  const low = current < sorted[cut] ? sorted[0] : sorted[cut]
  const high = current > sorted.at(-1 - cut) ? sorted.at(-1) : sorted.at(-1 - cut)
  const flat = sorted[0] === sorted.at(-1)
  const count = flat ? 1 : Math.min(12, Math.ceil(Math.sqrt(values.length)))
  const padding = high === low ? Math.max(0.1, Math.abs(low) * 0.01) : 0
  const start = low - padding
  const width = (high - low + padding * 2) / count
  const index = value => Math.max(0, Math.min(count - 1, Math.floor((value - start) / width)))
  const bins = Array.from({ length: count }, (_, i) => ({ from: start + i * width, to: start + (i + 1) * width, count: 0, current: i === index(current) }))
  for (const value of values) bins[index(value)].count++
  if (sorted[0] < low) bins[0].open = "below"
  if (sorted.at(-1) > high) bins.at(-1).open = "above"
  return bins
}
