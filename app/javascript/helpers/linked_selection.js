import { bisectLeft } from "d3-array"

const DAY = 86400000

let runs = []
let times = []
let current = null
let pending = null
let frame = null
const listeners = new Set()

export function dayStart(time) {
  return Math.floor(time / DAY) * DAY
}

export function weekStart(time) {
  const day = Math.floor(time / DAY)
  return (day - ((day + 3) % 7)) * DAY
}

export function quadrant(points, x, y) {
  return points.filter(point => point.x > x && point.y < y).map(point => point.index)
}

export function indicesInRange(sorted, from, to) {
  const indexes = []
  for (let index = bisectLeft(sorted, from); index < sorted.length && sorted[index] < to; index++) indexes.push(index)
  return indexes
}

export function bucketOf(starts, time) {
  let low = 0
  let high = starts.length
  while (low < high) {
    const middle = (low + high) >> 1
    if (starts[middle] <= time) low = middle + 1
    else high = middle
  }
  return low - 1
}

export function bucketSpan(starts, index, granularity) {
  const from = starts[index]
  if (index + 1 < starts.length) return [from, starts[index + 1]]
  const date = new Date(from)
  const to = granularity === "month" ? Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1) : from + (granularity === "week" ? 7 : 1) * DAY
  return [from, to]
}

export function bucketShares(list, starts, selected, weight) {
  const total = new Array(starts.length).fill(0)
  const chosen = new Array(starts.length).fill(0)
  list.forEach((run, index) => {
    const bucket = bucketOf(starts, run.t)
    if (bucket < 0) return
    const amount = weight(run) ?? 0
    total[bucket] += amount
    if (selected.has(index)) chosen[bucket] += amount
  })
  return total.map((sum, bucket) => (sum > 0 ? chosen[bucket] / sum : null))
}

export function selectionMean(list, selected, key) {
  let count = 0
  let km = 0
  let sum = 0
  let weight = 0
  for (const index of selected) {
    const run = list[index]
    if (run[key] == null) continue
    count++
    km += run.km
    sum += key === "pace" ? run[key] * run.km : run[key]
    weight += run.km
  }
  return count ? { km: km / count, value: key === "pace" ? sum / weight : sum / count } : null
}

export function levelKeys(cells, level) {
  return new Set(cells.filter(cell => cell.level === level).map(cell => cell.from))
}

export function runsInKeys(sorted, keyOf, keys) {
  return sorted.flatMap((time, index) => (keys.has(keyOf(time)) ? [index] : []))
}

export function keysOf(sorted, selected, keyOf) {
  const keys = new Set()
  for (const index of selected) keys.add(keyOf(sorted[index]))
  return keys
}

export function cellSelected(cell, step, span, keys) {
  if (span) return cell.from < span[1] && cell.from + step * DAY > span[0]
  return keys.has(cell.from)
}

export function spanSelection(sorted, from, to, source) {
  return { runs: new Set(indicesInRange(sorted, from, to)), span: [from, to], source }
}

export function setRuns(list) {
  runs = list
  times = list.map(run => run.t)
}

export function clearRuns(list) {
  if (runs === list) setRuns([])
}

export function getRuns() {
  return runs
}

export function getTimes() {
  return times
}

export function sameSelection(a, b) {
  if (!a || !b) return a === b
  if (a.source !== b.source || a.runs.size !== b.runs.size || String(a.span) !== String(b.span)) return false
  for (const index of a.runs) if (!b.runs.has(index)) return false
  return true
}

export function publish(selection) {
  if (sameSelection(frame ? pending : current, selection)) return
  pending = selection
  frame ||= requestAnimationFrame(flush)
}

export function clearSelection() {
  if (current || pending) publish(null)
}

export function subscribe(listener) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
    if (!listeners.size) {
      if (frame) cancelAnimationFrame(frame)
      frame = null
      pending = current = null
    }
  }
}

function flush() {
  frame = null
  current = pending
  for (const listener of listeners) listener(current)
}
