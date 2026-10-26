process.env.TZ = "Europe/Ljubljana"

import assert from "node:assert/strict"
import { existsSync } from "node:fs"
import { registerHooks } from "node:module"
import { test } from "node:test"
import { pathToFileURL } from "node:url"

const root = new URL("../../", import.meta.url)

registerHooks({
  resolve(specifier, context, next) {
    const vendored = new URL(`vendor/javascript/${specifier}.js`, root)
    if (/^(d3|internmap)/.test(specifier) && existsSync(vendored)) return { url: vendored.href, shortCircuit: true, format: "module" }
    if (specifier.startsWith("helpers/")) return { url: pathToFileURL(new URL(`app/javascript/${specifier}.js`, root).pathname).href, shortCircuit: true }
    return next(specifier, context)
  }
})

const L = await import("helpers/linked_selection")

const DAY = 86400000
const utc = (y, m, d, h = 0) => Date.UTC(y, m - 1, d, h)

test("day and week starts use UTC and Monday", () => {
  assert.equal(L.dayStart(utc(2026, 10, 26, 23)), utc(2026, 10, 26))
  assert.equal(L.weekStart(utc(2026, 10, 26, 5)), utc(2026, 10, 26))
  assert.equal(L.weekStart(utc(2026, 11, 1, 23)), utc(2026, 10, 26))
  assert.equal(L.weekStart(utc(2026, 11, 2)), utc(2026, 11, 2))
  assert.equal(L.weekStart(utc(2024, 1, 1)), utc(2024, 1, 1))
})

test("quadrant keeps runs strictly longer and strictly higher than the cursor", () => {
  const points = [
    { x: 10, y: 10, index: 0 },
    { x: 20, y: 5, index: 1 },
    { x: 20, y: 10, index: 2 },
    { x: 10, y: 5, index: 3 },
    { x: 30, y: 40, index: 4 }
  ]

  assert.deepEqual(L.quadrant(points, 10, 10), [1])
  assert.deepEqual(L.quadrant(points, 5, 50), [0, 1, 2, 3, 4])
  assert.deepEqual(L.quadrant(points, 40, 0), [])
  assert.deepEqual(L.quadrant([], 1, 1), [])
})

test("trailing windows select runs in the N days ending that day", () => {
  const times = [utc(2026, 1, 1, 7), utc(2026, 1, 3, 7), utc(2026, 1, 3, 18), utc(2026, 1, 10, 7)]
  const end = utc(2026, 1, 3) + DAY

  assert.deepEqual([...L.spanSelection(times, end - 3 * DAY, end, "trailing").runs], [0, 1, 2])
  assert.deepEqual([...L.spanSelection(times, end - 2 * DAY, end, "trailing").runs], [1, 2])
  assert.deepEqual([...L.spanSelection(times, end - DAY, end, "trailing").runs], [1, 2])
  assert.deepEqual([...L.spanSelection(times, utc(2026, 1, 4), utc(2026, 1, 9), "streak").runs], [])
  assert.deepEqual(L.spanSelection(times, 0, 10, "x").span, [0, 10])
  assert.deepEqual([...L.spanSelection([], 0, 10, "x").runs], [])
})

test("the end of a span is exclusive and the start inclusive", () => {
  const times = [utc(2026, 1, 1), utc(2026, 1, 2)]

  assert.deepEqual(L.indicesInRange(times, utc(2026, 1, 1), utc(2026, 1, 2)), [0])
  assert.deepEqual(L.indicesInRange(times, utc(2026, 1, 1) + 1, utc(2026, 1, 3)), [1])
})

test("runs map to the last bucket starting at or before them", () => {
  const starts = [utc(2026, 1, 1), utc(2026, 2, 1), utc(2026, 3, 1)]

  assert.equal(L.bucketOf(starts, utc(2026, 1, 1)), 0)
  assert.equal(L.bucketOf(starts, utc(2026, 1, 31, 23)), 0)
  assert.equal(L.bucketOf(starts, utc(2026, 2, 1)), 1)
  assert.equal(L.bucketOf(starts, utc(2026, 12, 1)), 2)
  assert.equal(L.bucketOf(starts, utc(2025, 12, 31)), -1)
})

test("a period spans to the next period's start, and the last one to the end of its own", () => {
  const months = [utc(2026, 1, 1), utc(2026, 2, 1), utc(2026, 12, 1)]
  const weeks = [utc(2026, 10, 19), utc(2026, 10, 26)]

  assert.deepEqual(L.bucketSpan(months, 0, "month"), [utc(2026, 1, 1), utc(2026, 2, 1)])
  assert.deepEqual(L.bucketSpan(months, 2, "month"), [utc(2026, 12, 1), utc(2027, 1, 1)])
  assert.deepEqual(L.bucketSpan(weeks, 1, "week"), [utc(2026, 10, 26), utc(2026, 11, 2)])
  assert.deepEqual(L.bucketSpan([utc(2026, 10, 26)], 0, "day"), [utc(2026, 10, 26), utc(2026, 10, 27)])
  assert.deepEqual(L.indicesInRange([utc(2026, 12, 31)], ...L.bucketSpan(months, 2, "month")), [0])
})

test("bucket shares weigh the selected runs inside each bar", () => {
  const starts = [utc(2026, 1, 1), utc(2026, 2, 1), utc(2026, 3, 1)]
  const runs = [
    { t: utc(2026, 1, 5), km: 10, elev: 100 },
    { t: utc(2026, 1, 9), km: 30, elev: null },
    { t: utc(2026, 2, 5), km: 5, elev: 50 },
    { t: utc(2025, 12, 5), km: 99, elev: 99 }
  ]

  assert.deepEqual(L.bucketShares(runs, starts, new Set([0]), run => run.km), [0.25, 0, null])
  assert.deepEqual(L.bucketShares(runs, starts, new Set([0, 1, 2]), run => run.km), [1, 1, null])
  assert.deepEqual(L.bucketShares(runs, starts, new Set([0]), run => run.elev), [1, 0, null])
  assert.deepEqual(L.bucketShares(runs, starts, new Set([0]), () => 1), [0.5, 0, null])
  assert.deepEqual(L.bucketShares(runs, starts, new Set(), run => run.km), [0, 0, null])
})

test("the selection mean is km weighted for pace and plain otherwise, skipping runs without a value", () => {
  const runs = [
    { km: 10, pace: 300, hr: 150 },
    { km: 30, pace: 360, hr: null },
    { km: 20, pace: 330, hr: 130 }
  ]

  assert.deepEqual(L.selectionMean(runs, new Set([0, 1]), "pace"), { km: 20, value: 345 })
  assert.deepEqual(L.selectionMean(runs, new Set([0, 1, 2]), "hr"), { km: 15, value: 140 })
  assert.equal(L.selectionMean(runs, new Set(), "pace"), null)
  assert.equal(L.selectionMean(runs, new Set([1]), "hr"), null)
})

test("legend levels select every run in that level's cells", () => {
  const cells = [
    { from: utc(2026, 1, 5), level: 3 },
    { from: utc(2026, 1, 12), level: 1 },
    { from: utc(2026, 1, 19), level: 3 },
    { from: utc(2026, 1, 26), level: 0 }
  ]
  const times = [utc(2026, 1, 6), utc(2026, 1, 11), utc(2026, 1, 13), utc(2026, 1, 25, 23), utc(2026, 1, 21)]
  const keys = L.levelKeys(cells, 3)

  assert.deepEqual([...keys], [utc(2026, 1, 5), utc(2026, 1, 19)])
  assert.deepEqual(L.runsInKeys(times.slice().sort((a, b) => a - b), L.weekStart, keys), [0, 1, 3, 4])
  assert.deepEqual(L.runsInKeys(times, L.weekStart, L.levelKeys(cells, 9)), [])
})

test("a heatmap cell is selected by a span overlap or by holding a selected run", () => {
  const step = 7
  const week = { from: utc(2026, 1, 5) }
  const times = [utc(2026, 1, 7), utc(2026, 1, 20)]

  assert.equal(L.cellSelected(week, step, [utc(2026, 1, 11), utc(2026, 1, 13)], null), true)
  assert.equal(L.cellSelected(week, step, [utc(2026, 1, 12), utc(2026, 1, 13)], null), false)
  assert.equal(L.cellSelected(week, step, [utc(2025, 12, 29), utc(2026, 1, 5)], null), false)
  assert.equal(L.cellSelected(week, step, [utc(2025, 12, 29), utc(2026, 1, 5) + 1], null), true)
  assert.equal(L.cellSelected(week, step, null, L.keysOf(times, new Set([0]), L.weekStart)), true)
  assert.equal(L.cellSelected(week, step, null, L.keysOf(times, new Set([1]), L.weekStart)), false)
  assert.equal(L.cellSelected({ from: utc(2026, 1, 7) }, 1, null, L.keysOf(times, new Set([0]), L.dayStart)), true)
  assert.equal(L.cellSelected({ from: utc(2026, 1, 8) }, 1, null, L.keysOf(times, new Set([0]), L.dayStart)), false)
})

test("selections are the same when source, runs and span match", () => {
  const a = { runs: new Set([1, 2]), span: null, source: "scatter" }

  assert.equal(L.sameSelection(a, { runs: new Set([2, 1]), span: null, source: "scatter" }), true)
  assert.equal(L.sameSelection(a, { runs: new Set([1, 3]), span: null, source: "scatter" }), false)
  assert.equal(L.sameSelection(a, { runs: new Set([1]), span: null, source: "scatter" }), false)
  assert.equal(L.sameSelection(a, { runs: new Set([1, 2]), span: null, source: "bars" }), false)
  assert.equal(L.sameSelection(a, { runs: new Set([1, 2]), span: [1, 2], source: "scatter" }), false)
  assert.equal(L.sameSelection({ runs: new Set(), span: [1, 2], source: "s" }, { runs: new Set(), span: [1, 2], source: "s" }), true)
  assert.equal(L.sameSelection(null, null), true)
  assert.equal(L.sameSelection(a, null), false)
  assert.equal(L.sameSelection(null, a), false)
})
