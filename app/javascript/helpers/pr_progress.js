import { predictTime } from "helpers/predictions"
import { formatDuration } from "helpers/formatters"

const DAY = 86400000

export function parseRuns({ columns, runs }) {
  return runs.map(row => Object.fromEntries(columns.map((column, index) => [column, row[index]])))
}

export function windowBest(runs, [start, end], count) {
  const best = new Array(count)
  for (const run of runs) {
    if (run.time >= end) break
    if (run.time < start || run.bucket == null) continue
    if (!best[run.bucket] || run.best < best[run.bucket].best) best[run.bucket] = run
  }
  return best
}

function lastDayOf(end) {
  return Math.ceil(end / DAY) - 1
}

export function daysSince(runs, end, count) {
  const last = new Array(count)
  for (const run of runs) {
    if (run.time >= end) break
    if (run.bucket != null) last[run.bucket] = run
  }
  const lastDay = lastDayOf(end)
  return Array.from(last, run => (run ? lastDay - Math.floor(run.time / DAY) : undefined))
}

export function daysSincePr(runs, end, count) {
  const lastDay = lastDayOf(end)
  return Array.from(windowBest(runs, [-Infinity, end], count), run => (run ? lastDay - Math.floor(run.time / DAY) : undefined))
}

export function percentSlower(best, record) {
  return ((best - record) / record) * 100
}

export function recordsByBucket(frontier, count) {
  const records = new Array(count)
  for (const record of frontier) records[record.bucket] = record
  return records
}

export function predictions(benchmarks, records, spi) {
  return benchmarks.map(({ meters, table }, bucket) => {
    const time = predictTime(table, spi)
    const record = records[bucket]
    return {
      bucket,
      time,
      pace: (time / meters) * 1000,
      change: record ? ((record.time - time) / record.time) * 100 : null,
      beats: !record || time < record.time
    }
  })
}

export function subLabel(seconds) {
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const rest = Math.round(seconds % 60)
  if (rest) return formatDuration(seconds)
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, "0")}` : String(minutes)
}

export function magicText(name, target, record, percent) {
  return `Sub-${subLabel(target)} ${name.toLowerCase()}: shave ${formatDuration(record - target)} (${percent.toFixed(1)}%)`
}
