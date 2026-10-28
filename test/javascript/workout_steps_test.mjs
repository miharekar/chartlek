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

const { labelled, stepAt, stepPace, stepRows } = await import("helpers/workout_steps")

const steps = [
  { type: "warmup", from: 0, to: 1000, time: 360 },
  { type: "active", from: 1000, to: 1400, time: 80 },
  { type: "recovery", from: 1400, to: 1600, time: 100 },
  { type: "active", from: 1600, to: 2000, time: 84 },
  { type: "cooldown", from: 2000, to: 2500, time: 200 }
]

test("labelled numbers repeated types and leaves single steps plain", () => {
  assert.deepEqual(labelled(steps).map(step => step.label), ["Warm-up", "Active 1 of 2", "Recovery", "Active 2 of 2", "Cool-down"])
  assert.equal(labelled(steps)[1].from, 1000)
  assert.deepEqual(labelled([]), [])
})

test("stepAt finds the step holding a distance, with the end inside the last step", () => {
  assert.equal(stepAt(steps, 0).type, "warmup")
  assert.equal(stepAt(steps, 999.9).type, "warmup")
  assert.equal(stepAt(steps, 1000).type, "active")
  assert.equal(stepAt(steps, 1700).type, "active")
  assert.equal(stepAt(steps, 2500).type, "cooldown")
  assert.equal(stepAt(steps, 2600), null)
  assert.equal(stepAt([], 10), null)
})

test("stepPace is seconds per km from the step's own time and distance", () => {
  assert.equal(stepPace(steps[1]), 200)
  assert.equal(stepPace({ from: 5, to: 5, time: 3 }), null)
})

test("stepRows lists distance, time and pace, skipping the pace of a zero-length step", () => {
  assert.deepEqual(stepRows(steps[1]), [["Distance", "0.4 km"], ["Time", "1:20"], ["Pace", "3:20 /km"]])
  assert.equal(stepRows({ from: 5, to: 5, time: 3 })[2], false)
})
