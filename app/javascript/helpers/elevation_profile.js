export const FLAT_RANGE_M = 150
export const FLOOR_M = 5

export function profilePoints(distances, altitudes) {
  return distances.flatMap((distance, index) => (altitudes[index] == null ? [] : [{ km: distance / 1000, alt: altitudes[index] }]))
}

export function profileDomain(points) {
  const low = Math.min(...points.map(point => point.alt))
  const high = Math.max(...points.map(point => point.alt))
  return [low - FLOOR_M, Math.max(low + FLAT_RANGE_M, high)]
}

export function peakPoint(points) {
  return points.reduce((top, point) => (point.alt > top.alt ? point : top))
}
