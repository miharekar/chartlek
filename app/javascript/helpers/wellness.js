import { bisector } from "d3-array"

const DAY_MS = 86400000
const BY_TIME = bisector(point => point[0])

export function movingMean(values, before, after, minValues = 1) {
  const sums = [0]
  const counts = [0]
  for (const value of values) {
    sums.push(sums.at(-1) + (value ?? 0))
    counts.push(counts.at(-1) + (value == null ? 0 : 1))
  }

  return values.map((_, index) => {
    const low = Math.max(0, index - before)
    const high = Math.min(values.length, index + after + 1)
    const count = counts[high] - counts[low]
    return count && counts[index + 1] >= minValues ? (sums[high] - sums[low]) / count : null
  })
}

export function dayIndex(start, ms) {
  return Math.round((ms - start) / DAY_MS)
}

export function stackZones(seconds) {
  let top = 0
  return seconds.map((value, index) => ({ zone: index + 1, from: top, to: (top += value) }))
}

export function pointAtOrBefore(points, ms) {
  return points[BY_TIME.right(points, ms) - 1]
}

export function weekAt(weeks, ms) {
  const week = pointAtOrBefore(weeks, ms)
  return week && ms < week[0] + 7 * DAY_MS ? week : undefined
}
