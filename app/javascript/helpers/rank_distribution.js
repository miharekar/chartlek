export function distribution(values, current) {
  if (!values.length) return []
  const low = Math.min(...values)
  const high = Math.max(...values)
  const count = high === low ? 1 : Math.min(12, Math.ceil(Math.sqrt(values.length)))
  const padding = high === low ? Math.max(0.1, Math.abs(low) * 0.01) : 0
  const start = low - padding
  const width = (high - low + padding * 2) / count
  const index = value => Math.max(0, Math.min(count - 1, Math.floor((value - start) / width)))
  const bins = Array.from({ length: count }, (_, i) => ({ from: start + i * width, to: start + (i + 1) * width, count: 0, current: i === index(current) }))
  for (const value of values) bins[index(value)].count++
  return bins
}
