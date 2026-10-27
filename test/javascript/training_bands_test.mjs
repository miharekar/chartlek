import assert from "node:assert/strict"
import { existsSync } from "node:fs"
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

const { WEEK_MS, groupRows, peak, stackBands, visibleBands, weekIndex, weekTotals } = await import("helpers/training_bands")

const category = {
  groups: [{ label: "Easy", bands: [0, 1] }, { label: "Hard", bands: [2] }],
  bands: { 0: [3600, 0, 0], 1: [3600, 7200, 0], 2: [0, 3600, 3600] }
}

test("weekIndex counts whole weeks from the start", () => {
  assert.equal(weekIndex(0, 0), 0)
  assert.equal(weekIndex(0, WEEK_MS - 1), 0)
  assert.equal(weekIndex(0, WEEK_MS), 1)
  assert.equal(weekIndex(WEEK_MS, 0), -1)
})

test("weekTotals sums every band", () => {
  assert.deepEqual(weekTotals(category, 3), [7200, 10800, 3600])
})

test("visibleBands drops hidden groups", () => {
  assert.deepEqual(visibleBands(category, new Set()), [0, 1, 2])
  assert.deepEqual(visibleBands(category, new Set([0])), [2])
  assert.deepEqual(visibleBands(category, new Set([0, 1])), [])
})

test("stackBands stacks hours and chains the layers", () => {
  const { layers, top } = stackBands(category, [0, 2], [7200, 10800, 3600], false)

  assert.deepEqual(layers[0].lower, [0, 0, 0])
  assert.deepEqual(layers[0].upper, [1, 0, 0])
  assert.deepEqual(layers[1].lower, layers[0].upper)
  assert.deepEqual(top, [1, 1, 1])
})

test("stackBands percent is the share of the whole week, so hidden bands leave a gap", () => {
  const { top } = stackBands(category, [2], [7200, 10800, 3600], true)

  assert.deepEqual(top.map(Math.round), [0, 33, 100])
})

test("stackBands percent of an empty week is zero", () => {
  assert.deepEqual(stackBands(category, [0], [0, 0, 0], true).top, [0, 0, 0])
})

test("peak is the highest top in the span, clamped", () => {
  assert.equal(peak([1, 5, 2, 9], 0, 3), 5)
  assert.equal(peak([1, 5, 2, 9], -2, 10), 9)
  assert.equal(peak([], 0, 3), 0)
})

test("groupRows lists visible groups with seconds and share", () => {
  const totals = weekTotals(category, 3)

  assert.deepEqual(groupRows(category, 1, new Set(), totals), [{ label: "Easy", seconds: 7200, share: (7200 / 10800) * 100 }, { label: "Hard", seconds: 3600, share: (3600 / 10800) * 100 }])
  assert.deepEqual(groupRows(category, 1, new Set([0]), totals).map(row => row.label), ["Hard"])
  assert.deepEqual(groupRows(category, 0, new Set(), totals).map(row => row.label), ["Easy"])
})
