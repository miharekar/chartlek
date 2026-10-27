import assert from "node:assert/strict"
import { test } from "node:test"

const { bins, bucketLabels, bucketOf, buildSegments, distribution, nextSelection, paceZone, selectionStats, selectionWeights } = await import(new URL("../../app/javascript/helpers/pro_map.js", import.meta.url))

const data = {
  t: [0, 30, 60, 90, 120],
  d: [0, 100, 200, 300, 400],
  alt: [100, 102, 104, 104, 104],
  hr: [140, 150, 160, 170, 180],
  cad: [170, 170, 170, null, null],
  lat: [46, 46.001, null, 46.003, 46.004],
  lng: [14, 14.001, null, 14.003, 14.004]
}

test("paceZone follows the Ruby zones", () => {
  assert.equal(paceZone(5.4), 0)
  assert.equal(paceZone(5.5), 1)
  assert.equal(paceZone(12), 14)
  assert.equal(paceZone(30), 36)
})

test("bucketOf covers every metric and clamps the extremes", () => {
  const floors = [100, 120, 140, 160, 180]
  assert.equal(bucketOf("hr", 90, floors), 0)
  assert.equal(bucketOf("hr", 150, floors), 2)
  assert.equal(bucketOf("grade", -25, []), 0)
  assert.equal(bucketOf("grade", 0, []), 5)
  assert.equal(bucketOf("grade", 40, []), 9)
  assert.equal(bucketOf("cadence", 149, []), 0)
  assert.equal(bucketOf("cadence", 175, []), 3)
  assert.equal(bucketOf("cadence", 200, []), 5)
  assert.equal(bucketOf("pace", null, []), null)
})

test("bucketLabels has one label per bucket", () => {
  assert.equal(bucketLabels("grade").length, 10)
  assert.equal(bucketLabels("cadence").length, 6)
  assert.deepEqual(bucketLabels("hr", { floors: [100, 120, 140, 160, 180] }).map(it => it.label), ["Z1", "Z2", "Z3", "Z4", "Z5"])
  assert.equal(bucketLabels("hr", { floors: [100, 120, 140, 160, 180] })[4].title, "Zone 5, 180+ bpm")
})

test("buildSegments smooths pace and grade and keeps gaps without GPS", () => {
  const segments = buildSegments(data)
  assert.equal(segments.length, 4)
  assert.equal(segments[0].distance, 100)
  assert.ok(Math.abs(segments[0].kmh - 12) < 1e-9)
  assert.ok(Math.abs(segments[0].grade - 2) < 1e-9)
  assert.equal(segments[0].hr, 145)
  assert.equal(segments[3].cad, null)
  assert.deepEqual(segments[0].line, [[14, 46], [14.001, 46.001]])
  assert.equal(segments[1].line, null)
  assert.deepEqual(segments[2].line, [[14.001, 46.001], [14.003, 46.003]])
})

test("nextSelection runs the four-click cycle and restarts on another bucket", () => {
  let selection = nextSelection(null, 3)
  assert.deepEqual(selection, { bucket: 3, step: 1 })
  selection = nextSelection(selection, 3)
  assert.deepEqual(selection, { bucket: 3, step: 2 })
  selection = nextSelection(selection, 3)
  assert.deepEqual(selection, { bucket: 3, step: 3 })
  assert.equal(nextSelection(selection, 3), null)
  assert.deepEqual(nextSelection(selection, 4), { bucket: 4, step: 1 })
})

test("selectionWeights picks buckets by step and overlaps ranges", () => {
  const segments = buildSegments(data)
  const buckets = [1, 2, 3, 4]
  assert.equal(selectionWeights(segments, buckets, null), null)
  assert.deepEqual(selectionWeights(segments, buckets, { bucket: 2, step: 1 }), [0, 1, 0, 0])
  assert.deepEqual(selectionWeights(segments, buckets, { bucket: 2, step: 2 }), [0, 1, 1, 1])
  assert.deepEqual(selectionWeights(segments, buckets, { bucket: 2, step: 3 }), [1, 1, 0, 0])
  assert.deepEqual(selectionWeights(segments, buckets, { from: 50, to: 250 }), [0.5, 1, 0.5, 0])
})

test("selectionStats weights distance, time and averages", () => {
  const segments = buildSegments(data)
  const all = selectionStats(segments, null)
  assert.equal(all.distance, 400)
  assert.equal(all.time, 120)
  assert.equal(all.pace, 300)
  assert.equal(all.hr, 160)
  assert.equal(all.cad, 170)

  const part = selectionStats(segments, [1, 0, 0.5, 0])
  assert.equal(part.distance, 150)
  assert.equal(part.time, 45)
  assert.ok(Math.abs(part.hr - 151.6666666667) < 1e-6)
  assert.equal(selectionStats(segments, [0, 0, 0, 0]).pace, null)
})

test("distribution totals distance and time per bucket and skips missing values", () => {
  const segments = buildSegments(data)
  const totals = distribution(segments, [0, 1, 1, null], 3)
  assert.deepEqual(totals[1], { distance: 200, time: 60 })
  assert.deepEqual(totals[2], { distance: 0, time: 0 })
})

test("bins split segments across 100 m bars and mark the selection", () => {
  const segments = buildSegments({ t: [0, 60, 120], d: [0, 150, 300], alt: [0, 3, 6] })
  const result = bins(segments, null)
  assert.equal(result.length, 3)
  assert.ok(result.every(bin => Math.abs(bin.distance - 100) < 1e-9))
  assert.ok(result.every(bin => Math.abs(bin.pace - 400) < 1e-9))
  assert.ok(result.every(bin => Math.abs(bin.grade - 2) < 1e-9))
  assert.ok(result.every(bin => bin.hr === null && bin.selected))

  assert.deepEqual(bins(segments, [1, 0]).map(bin => bin.selected), [true, true, false])
})

test("bins leave pace undefined where distance advances with no time", () => {
  const segments = buildSegments({ t: [0, 30, 30, 30, 60], d: [0, 100, 200, 300, 400] })
  const result = bins(segments, null)
  assert.equal(result[1].time, 0)
  assert.equal(result[1].pace, null)
  assert.equal(result[2].pace, null)
  assert.ok(result.filter(bin => bin.pace != null).every(bin => Number.isFinite(bin.pace) && bin.pace > 0))
})
