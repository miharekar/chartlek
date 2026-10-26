import { formatDuration, formatPace } from "helpers/formatters"

export function speedWindows(distances) {
  const mean = distances.reduce((sum, distance) => sum + distance, 0) / distances.length
  if (distances.length < 2 || !(mean > 0)) return []
  return distances.map((distance, index) => {
    const deviation = (distance - mean) / mean * 100
    return {
      from: index * 10, to: (index + 1) * 10,
      up: Math.max(0, deviation), down: Math.max(0, -deviation),
      lines: [`${formatDuration(index * 10)}–${formatDuration((index + 1) * 10)} timer time`, distance === 0 ? "Stopped" : `${formatPace(10000 / distance)} /km`, `${deviation > 0 ? "+" : ""}${deviation.toFixed(1)}% vs average speed`]
    }
  })
}

export function elevationBins(bins, perKm = false) {
  const grouped = []
  for (let index = 0; index < bins.length; index += perKm ? 10 : 1) {
    const part = bins.slice(index, index + (perKm ? 10 : 1))
    const known = part.filter(bin => bin.gain != null)
    grouped.push({
      distance: part.reduce((sum, bin) => sum + bin.distance, 0),
      gain: known.length ? known.reduce((sum, bin) => sum + bin.gain, 0) : null,
      loss: known.length ? known.reduce((sum, bin) => sum + bin.loss, 0) : null,
      missing: part.some(bin => bin.missing || bin.gain == null)
    })
  }
  let distance = 0
  return grouped.map(bin => {
    const from = distance / 1000
    distance += bin.distance
    const to = distance / 1000
    const lines = [`${from.toFixed(3)}–${to.toFixed(3)} km`]
    if (bin.gain != null) lines.push(`Gained ${bin.gain.toFixed(1)} m; lost ${bin.loss.toFixed(1)} m`)
    if (bin.missing) lines.push(bin.gain == null ? "Elevation missing" : "Some elevation missing; known changes only")
    return { from, to, up: bin.gain, down: bin.loss, lines }
  })
}
