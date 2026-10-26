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
  for (const [value, seconds] of vdotTable10k) assert.equal(predictTime(vdotTable10k, value), seconds)
})

test("predictTime interpolates linearly between rows", () => {
  assert.ok(Math.abs(predictTime(vdotTable10k, 40) - (3828.9 + 2479.6) / 2) < 1e-9)
})

test("predictTime clamps outside the table", () => {
  assert.equal(predictTime(vdotTable10k, 5), 8813.3)
  assert.equal(predictTime(vdotTable10k, 120), 1505.1)
})

test("predictTime falls as the value rises", () => {
  assert.ok(predictTime(vdotTable10k, 60) < predictTime(vdotTable10k, 50))
})
