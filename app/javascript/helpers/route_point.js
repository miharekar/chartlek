import { bisector } from "d3-array"

export const MAX_GAP_M = 100
const EDGE_M = 25

const BY_DISTANCE = bisector(distance => distance)

export function routeAt(route, distances, distance) {
  if (!route.length || route.length !== distances.length) return null
  if (distance < distances[0] - EDGE_M || distance > distances.at(-1) + EDGE_M) return null
  if (route.length === 1) return route[0]

  const target = Math.max(distances[0], Math.min(distances.at(-1), distance))
  const next = Math.min(distances.length - 1, Math.max(1, BY_DISTANCE.right(distances, target)))
  const span = distances[next] - distances[next - 1]
  if (span > MAX_GAP_M) return null

  const share = span > 0 ? (target - distances[next - 1]) / span : 0
  const [fromLng, fromLat] = route[next - 1]
  const [toLng, toLat] = route[next]

  return [fromLng + (toLng - fromLng) * share, fromLat + (toLat - fromLat) * share]
}
