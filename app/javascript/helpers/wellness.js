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
    return count >= minValues ? (sums[high] - sums[low]) / count : null
  })
}

export function weightTrend(values) {
  const first = values.findIndex(value => value != null)
  const last = values.findLastIndex(value => value != null)
  const means = movingMean(values, 15, 15).map((mean, index) => (index < first || index > last ? null : mean))
  let before = first
  for (let index = first + 1; index <= last; index++) {
    if (means[index] == null) continue
    for (let gap = before + 1; gap < index; gap++) means[gap] = means[before] + ((means[index] - means[before]) * (gap - before)) / (index - before)
    before = index
  }
  return means
}

export function dailyAverage(values) {
  return movingMean(values, 6, 0, 4).map((mean, index) => (values[index] == null ? null : mean))
}

export function clockLabel(seconds) {
  const minutes = ((Math.round(seconds / 60) % 1440) + 1440) % 1440
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`
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
