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

const { dayIndex, movingMean, pointAtOrBefore, stackZones, weekAt } = await import("helpers/wellness")

const DAY = 86400000

test("the 7-day average starts at the fourth value and skips days without one", () => {
  const values = [50, 52, null, 54, 56, null, null, null, null, null, null, 60]
  const average = movingMean(values, 6, 0, 4)

  assert.deepEqual(average.slice(0, 4), [null, null, null, null])
  assert.equal(average[4], 53)
  assert.equal(average[6], 53)
  assert.equal(average[7], 54)
  assert.equal(average[10], 56)
  assert.equal(average[11], 60)
})

test("the 7-day average has no value once the window holds none", () => {
  const average = movingMean([1, 2, 3, 4, null, null, null, null, null, null, null, null], 6, 0, 4)

  assert.equal(average[3], 2.5)
  assert.equal(average[10], null)
})

test("a centred mean averages the values on both sides and ignores gaps", () => {
  const trend = movingMean([70, null, 72, null, null, 74], 1, 1)

  assert.deepEqual(trend, [70, 71, 72, 72, 74, 74])
  assert.deepEqual(movingMean([], 1, 1), [])
})

test("dayIndex counts whole days from the start", () => {
  assert.equal(dayIndex(0, 3 * DAY), 3)
  assert.equal(dayIndex(0, 3 * DAY + DAY / 3), 3)
})

test("stackZones stacks the zones from the bottom", () => {
  assert.deepEqual(stackZones([60, 0, 30]), [
    { zone: 1, from: 0, to: 60 },
    { zone: 2, from: 60, to: 60 },
    { zone: 3, from: 60, to: 90 }
  ])
})

test("pointAtOrBefore and weekAt find the surrounding entry", () => {
  const points = [[10 * DAY, "a"], [20 * DAY, "b"]]

  assert.equal(pointAtOrBefore(points, 5 * DAY), undefined)
  assert.equal(pointAtOrBefore(points, 10 * DAY)[1], "a")
  assert.equal(pointAtOrBefore(points, 25 * DAY)[1], "b")
  assert.equal(weekAt(points, 16 * DAY)[1], "a")
  assert.equal(weekAt(points, 17 * DAY), undefined)
  assert.equal(weekAt(points, 5 * DAY), undefined)
})
