import assert from "node:assert/strict"
import { registerHooks } from "node:module"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

const root = new URL("../../", import.meta.url)

registerHooks({
  resolve(specifier, context, next) {
    if (specifier.startsWith("helpers/")) return { url: pathToFileURL(new URL(`app/javascript/${specifier}.js`, root).pathname).href, shortCircuit: true }
    return next(specifier, context)
  }
})

const { histogram, selectRuns, summarize, average, timelineTicks, daysBefore, sameDayRuns } = await import("helpers/analyze_run")

const runs = [
  { km: 5, pace: 300, hr: 150, vdot: 50, s: 1500 },
  { km: 10, pace: 360, hr: null, vdot: null, s: 3600 },
  { km: 20, pace: 330, hr: 140, vdot: 60, s: 6600 },
  { km: 5, pace: 300, hr: 160, vdot: 55, s: 1500 }
]

test("histogram bins runs by distance and keeps the maximum in the last bin", () => {
  const bins = histogram(runs, "km", 3)

  assert.deepEqual(bins.map(bin => bin.runs), [[0, 3], [1], [2]])
  assert.equal(bins[0].x0, 5)
  assert.equal(bins[2].x1, 20)
})

test("histogram skips runs without the metric", () => {
  const bins = histogram(runs, "hr", 2)

  assert.deepEqual(bins.flatMap(bin => bin.runs).sort(), [0, 2, 3])
})

test("histogram bins pace linearly in speed", () => {
  const bins = histogram(runs, "pace", 2)

  assert.equal(bins[0].x0, 10)
  assert.equal(bins[1].x1, 12)
  assert.deepEqual(bins.map(bin => bin.runs), [[1, 2], [0, 3]])
})

test("histogram handles identical values and no values", () => {
  assert.deepEqual(histogram([runs[0], runs[3]], "pace", 4).flatMap(bin => bin.runs), [0, 1])
  assert.deepEqual(histogram([runs[1]], "hr"), [])
  assert.deepEqual(histogram([], "km"), [])
})

test("selectRuns takes bins overlapping the range", () => {
  const bins = histogram(runs, "km", 3)

  assert.deepEqual([...selectRuns(bins, [5, 8])].sort(), [0, 3])
  assert.deepEqual([...selectRuns(bins, [10, 20])].sort(), [1, 2])
  assert.equal(selectRuns(bins, [100, 200]).size, 0)
})

test("summarize totals the selection against the window", () => {
  const summary = summarize(runs, new Set([0, 3]))

  assert.equal(summary.count, 2)
  assert.equal(summary.km, 10)
  assert.equal(summary.seconds, 3000)
  assert.equal(summary.share, 25)
})

test("summarize an empty selection", () => {
  assert.deepEqual(summarize(runs, new Set()), { count: 0, km: 0, seconds: 0, share: 0 })
  assert.equal(summarize([], new Set()).share, 0)
})

test("average takes the mean of the plotted metric and skips nulls", () => {
  assert.equal(average(runs, "km"), 10)
  assert.equal(average(runs, "hr"), 150)
  assert.equal(average(runs, "pace"), (3600 / 300 + 3600 / 360 + 3600 / 330 + 3600 / 300) / 4)
  assert.equal(average([runs[1]], "hr"), null)
  assert.equal(average([], "km"), null)
})

test("timeline ticks count days before the run day, ending on run day or race day", () => {
  const day = 86_400_000
  const to = Date.UTC(2024, 5, 10, 18)
  const from = Date.UTC(2024, 5, 10) - 90 * day

  assert.deepEqual(timelineTicks(from, to, false).map(tick => tick.label), ["90 days before", "60 days before", "30 days before", "run day"])
  assert.equal(timelineTicks(from, to, true).at(-1).label, "race day")
  assert.deepEqual(timelineTicks(from, to, false).map(tick => tick.t), [from, from + 30 * day, from + 60 * day, to])
})

test("daysBefore counts calendar days and sameDayRuns groups a day's runs", () => {
  const current = Date.UTC(2024, 5, 10, 18)
  const morning = { t: Date.UTC(2024, 5, 7, 7) }
  const evening = { t: Date.UTC(2024, 5, 7, 20) }
  const other = { t: Date.UTC(2024, 5, 8, 7) }

  assert.equal(daysBefore(current, morning.t), 3)
  assert.equal(daysBefore(current, Date.UTC(2024, 5, 10, 7)), 0)
  assert.equal(daysBefore(current, other.t), 2)
  assert.deepEqual(sameDayRuns([morning, evening, other], morning), [morning, evening])
  assert.deepEqual(sameDayRuns([morning, evening, other], other), [other])
})
