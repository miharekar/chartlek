export function rangeStats(bars, from, to) {
  let start = 0
  let distance = 0
  let time = 0
  const weighted = { hr: [0, 0], cad: [0, 0] }

  for (const bar of bars) {
    const overlap = Math.min(to, start + bar.distance) - Math.max(from, start)
    start += bar.distance
    if (overlap <= 0) continue

    const share = overlap / bar.distance
    distance += overlap
    time += bar.time * share
    for (const key of ["hr", "cad"]) {
      if (bar[key] == null) continue
      weighted[key][0] += bar[key] * bar.time * share
      weighted[key][1] += bar.time * share
    }
  }

  const average = ([sum, weight]) => (weight > 0 ? sum / weight : null)
  return { distance, time, pace: distance > 0 ? time / (distance / 1000) : null, hr: average(weighted.hr), cad: average(weighted.cad) }
}
