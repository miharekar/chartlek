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

const { histogram, selectRuns, summarize } = await import("helpers/analyze_run")

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
