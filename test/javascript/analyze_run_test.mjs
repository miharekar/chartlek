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

const { METRICS, average, axis, brushSelection, dayLabel, daysBefore, edgeLabelPositions, formatValue, groupDays, lit, nextReadout, niceTicks, readoutText, summarize, timelineTicks, valueOrder } = await import("helpers/analyze_run")

const DAY = 86_400_000
const t0 = Date.UTC(2024, 2, 1, 7)
const runs = [
  { km: 5, pace: 300, hr: 150, vdot: 50, s: 1500, t: t0 },
  { km: 10, pace: 360, hr: 0, vdot: null, s: 3600, t: t0 + 2 * DAY },
  { km: 20, pace: 330, hr: 140, vdot: 60, s: 6600, t: t0 + 2 * DAY + 3600_000 },
  { km: 5, pace: 300, hr: 160, vdot: 55, s: 1500, t: t0 + 5 * DAY }
]

test("metrics read speed for pace and treat zero or missing HR and VDOT as unknown", () => {
  assert.equal(METRICS.pace(runs[0]), 12)
  assert.equal(METRICS.pace({ pace: 0 }), null)
  assert.equal(METRICS.hr(runs[1]), null)
  assert.equal(METRICS.hr({ hr: null }), null)
  assert.equal(METRICS.vdot(runs[1]), null)
})

test("distance axis runs from 0 to the longest run rounded up plus 1", () => {
  assert.deepEqual(axis("km", runs, { km: 8 }).domain, [0, 21])
  assert.deepEqual(axis("km", runs, { km: 21.1 }).domain, [0, 23])
})

test("pace axis is speed from 4 km/h to the fastest plus 1, and reaches a slower run", () => {
  assert.deepEqual(axis("pace", runs, { pace: 280 }).domain, [4, 3600 / 280 + 1])
  assert.deepEqual(axis("pace", [{ pace: 1200 }], { pace: 1000 }).domain, [3, 3600 / 1000 + 1])
})

test("vdot axis pads the lowest and highest by 1", () => {
  assert.deepEqual(axis("vdot", runs, { vdot: 52 }).domain, [49, 61])
})

test("heart rate axis rounds out to 10 bpm and never collapses, skipping zero", () => {
  assert.deepEqual(axis("hr", runs, { hr: 155 }).domain, [140, 160])
  assert.deepEqual(axis("hr", [{ hr: 150 }], { hr: 150 }).domain, [145, 155])
  assert.deepEqual(axis("hr", runs, { hr: null }).domain, [140, 160])
})

test("an axis with no values is a unit range", () => {
  assert.deepEqual(axis("hr", [{ hr: 0 }], { hr: null }).domain, [0, 1])
})

test("nice ticks come in 1, 2 or 5 steps, aiming for seven", () => {
  assert.deepEqual(niceTicks(0, 21), [0, 5, 10, 15, 20])
  assert.deepEqual(niceTicks(49, 61), [50, 52, 54, 56, 58, 60])
  assert.deepEqual(niceTicks(4, 5.5, 5), [4, 4.5, 5, 5.5])
  assert.deepEqual(niceTicks(3, 3), [3])
})

test("values format as pace, distance, VDOT and bpm", () => {
  assert.equal(formatValue("pace", 12), "5:00")
  assert.equal(formatValue("km", 5), "5")
  assert.equal(formatValue("km", 5.04, true), "5.0")
  assert.equal(formatValue("vdot", 50.25, true), "50.3")
  assert.equal(formatValue("hr", 149.6), "150")
})

test("edge labels stay inside the strip and never cross", () => {
  assert.deepEqual(edgeLabelPositions([100, 300], 600), [100, 300])
  assert.deepEqual(edgeLabelPositions([16, 200], 600), [36, 200])
  assert.deepEqual(edgeLabelPositions([400, 584], 600), [400, 564])
  assert.deepEqual(edgeLabelPositions([16, 20], 600), [36, 36])
  assert.deepEqual(edgeLabelPositions([570, 584], 600), [528, 564])
})

test("the average skips runs without the metric", () => {
  assert.equal(average(runs, "km"), 10)
  assert.equal(average(runs, "hr"), 150)
  assert.equal(average(runs, "vdot"), 55)
  assert.equal(average([{ hr: 0 }, { hr: null }], "hr"), null)
})

test("a brush selects values inside it, edges included, and never runs without the metric", () => {
  assert.deepEqual([...brushSelection(runs, "km", [5, 10])], [0, 1, 3])
  assert.deepEqual([...brushSelection(runs, "km", [5.1, 9.9])], [])
  assert.deepEqual([...brushSelection(runs, "hr", [0, 200])], [0, 2, 3])
  assert.deepEqual([...brushSelection(runs, "pace", [12, 12])], [0, 3])
})

test("value order sorts ascending, ties by time, and leaves out unknowns", () => {
  assert.deepEqual(valueOrder(runs, "km"), [0, 3, 1, 2])
  assert.deepEqual(valueOrder(runs, "hr"), [2, 0, 3])
  assert.deepEqual(valueOrder(runs, "pace"), [1, 2, 0, 3])
})

test("the readout cycles share, hours, distance and count", () => {
  const selected = new Set([0, 2])
  assert.equal(readoutText(runs, selected, "share"), "50%")
  assert.equal(readoutText(runs, selected, "hours"), "2.3 h")
  assert.equal(readoutText(runs, selected, "distance"), "25.0 km")
  assert.equal(readoutText(runs, selected, "count"), "2 runs")
  assert.equal(readoutText(runs, new Set([0]), "count"), "1 run")
  assert.equal(readoutText([], new Set(), "share"), "0%")
  assert.deepEqual(["share", "hours", "distance", "count", "share"].slice(0, 4).map(nextReadout), ["hours", "distance", "count", "share"])
})

test("summarize totals the selection and its share of the training distance", () => {
  const { count, km, seconds, share } = summarize(runs, new Set([0, 3]))
  assert.deepEqual([count, km, seconds, share], [2, 10, 3000, 25])
  assert.equal(summarize([], new Set()).share, 0)
})

test("timeline ticks run every 30 days back from the run day, labelled for race or run", () => {
  const to = Date.UTC(2024, 5, 10, 18)
  const from = Date.UTC(2024, 5, 10) - 90 * DAY
  assert.deepEqual(timelineTicks(from, to, false).map(tick => tick.label), ["90 days before", "60 days before", "30 days before", "run day"])
  assert.equal(timelineTicks(from, to, true).at(-1).label, "race day")
  assert.equal(timelineTicks(from, to, false).at(-1).t, Date.UTC(2024, 5, 10))
})

test("days before count calendar days, with yesterday and the run day named", () => {
  const now = Date.UTC(2024, 5, 10, 18)
  assert.equal(daysBefore(now, Date.UTC(2024, 5, 9, 23)), 1)
  assert.equal(dayLabel(now, Date.UTC(2024, 5, 9, 23), false), "yesterday")
  assert.equal(dayLabel(now, Date.UTC(2024, 5, 7, 6), false), "3 days before")
  assert.equal(dayLabel(now, Date.UTC(2024, 5, 10, 7), false), "run day")
  assert.equal(dayLabel(now, Date.UTC(2024, 5, 10, 7), true), "race day")
})

test("runs on one day group together, in day order", () => {
  assert.deepEqual(groupDays(runs), [
    { day: Date.UTC(2024, 2, 1), indexes: [0] },
    { day: Date.UTC(2024, 2, 3), indexes: [1, 2] },
    { day: Date.UTC(2024, 2, 6), indexes: [3] }
  ])
  assert.deepEqual(groupDays([runs[3], runs[0]]).map(({ indexes }) => indexes), [[1], [0]])
})

test("lit dots are a day's runs, limited to the brush when there is one", () => {
  assert.deepEqual(lit([1, 2], null), [1, 2])
  assert.deepEqual(lit([1, 2], new Set([2, 3])), [2])
  assert.deepEqual(lit([1], new Set([0])), [])
})
