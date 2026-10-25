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

const { predictTime } = await import("helpers/predictions")

const spiTable10k = [
  [1, 7707.8],
  [1.5, 7694.0],
  [2, 7680.2],
  [100, 5684.7],
  [300, 3714.9],
  [500, 2758.9],
  [996, 1684.1],
  [1000, 1678.8]
]

const vdotTable10k = [
  [10, 8813.3],
  [10.05, 8784.9],
  [10.1, 8756.7],
  [30, 3828.9],
  [50, 2479.6],
  [89.5, 1512.1],
  [90, 1505.1]
]

test("predictTime returns table rows exactly", () => {
  for (const [value, seconds] of spiTable10k) assert.equal(predictTime(spiTable10k, value), seconds)
  for (const [value, seconds] of vdotTable10k) assert.equal(predictTime(vdotTable10k, value), seconds)
})

test("predictTime interpolates linearly between rows", () => {
  assert.ok(Math.abs(predictTime(spiTable10k, 1.25) - 7700.9) < 1e-9)
  assert.ok(Math.abs(predictTime(spiTable10k, 200) - (5684.7 + 3714.9) / 2) < 1e-9)
  assert.ok(Math.abs(predictTime(spiTable10k, 998) - (1684.1 + 1678.8) / 2) < 1e-9)
  assert.ok(Math.abs(predictTime(vdotTable10k, 40) - (3828.9 + 2479.6) / 2) < 1e-9)
})

test("predictTime clamps outside the table", () => {
  assert.equal(predictTime(spiTable10k, 0), 7707.8)
  assert.equal(predictTime(spiTable10k, -50), 7707.8)
  assert.equal(predictTime(spiTable10k, 1200), 1678.8)
  assert.equal(predictTime(vdotTable10k, 5), 8813.3)
  assert.equal(predictTime(vdotTable10k, 120), 1505.1)
})

test("predictTime falls as the value rises", () => {
  assert.ok(predictTime(spiTable10k, 600) < predictTime(spiTable10k, 500))
})
