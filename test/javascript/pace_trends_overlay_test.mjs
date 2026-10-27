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
    const helper = new URL(`app/javascript/${specifier}.js`, root)
    if (specifier.startsWith("helpers/") && existsSync(helper)) return { url: pathToFileURL(helper.pathname).href, shortCircuit: true, format: "module" }
    return next(specifier, context)
  }
})

const { overlayAt, overlaySeries, overlayWithin } = await import("helpers/pace_trends_overlay")

const DAY = 86400000

test("hrv is the nightly value on a dense day grid", () => {
  const series = overlaySeries({ start: 0, hrv: [50, null, 60] }, "hrv")
  assert.deepEqual(series, [[0, 50], [DAY, null], [2 * DAY, 60]])
})

test("resting hr is the 7-day mean with four values in the window, and a gap on a day without one", () => {
  const series = overlaySeries({ start: 0, rhr: [50, 52, 54, 56, null, 60] }, "rhr")
  assert.deepEqual(series.map(point => point[1]), [null, null, null, 53, null, 54.4])
})

test("a missing series is empty", () => {
  assert.deepEqual(overlaySeries({ start: 0, hrv: [1] }, "rhr"), [])
  assert.deepEqual(overlaySeries(null, "hrv"), [])
})

test("within takes the half-open window", () => {
  const series = overlaySeries({ start: 0, hrv: [1, 2, 3, 4] }, "hrv")
  assert.deepEqual(overlayWithin(series, DAY, 3 * DAY).map(point => point[1]), [2, 3])
})

test("at finds the value of the day, and nothing in a gap or outside", () => {
  const series = overlaySeries({ start: 0, hrv: [1, null, 3] }, "hrv")
  assert.equal(overlayAt(series, DAY / 2), 1)
  assert.equal(overlayAt(series, DAY + 5), undefined)
  assert.equal(overlayAt(series, 2 * DAY + 5), 3)
  assert.equal(overlayAt(series, 3 * DAY), undefined)
  assert.equal(overlayAt(series, -1), undefined)
})

test("sleep is nightly hours on a dense day grid", () => {
  const series = overlaySeries({ start: 0, sleep: [27000, null, 21600] }, "sleep")
  assert.deepEqual(series, [[0, 7.5], [DAY, null], [2 * DAY, 6]])
})
