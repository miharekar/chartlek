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

const { speedWindows, elevationBins } = await import("helpers/recording_bars")

test("variability uses signed chronological deviations, not a scalar waveform", () => {
  const samples = speedWindows([20, 60, 20, 60])
  assert.deepEqual(samples.map(sample => sample.up - sample.down), [-50, 50, -50, 50])
  assert.deepEqual(samples.map(sample => [sample.from, sample.to]), [[0, 10], [10, 20], [20, 30], [30, 40]])
  assert.notDeepEqual(samples, speedWindows([60, 20, 60, 20]))
  assert(samples[0].lines.includes("8:20 /km"))
  assert(samples[1].lines.includes("+50.0% vs average speed"))
})

test("steady windows are zero, stopped windows are explicit and insufficient samples are empty", () => {
  assert(speedWindows([40, 40]).every(sample => sample.up === 0 && sample.down === 0))
  const stopped = speedWindows([0, 40])[0]
  assert.equal(stopped.down, 100)
  assert(stopped.lines.includes("Stopped"))
  assert.deepEqual(speedWindows([40]), [])
  assert.deepEqual(speedWindows([0, 0]), [])
})

test("km elevation bins sum the same gain and loss and keep partial widths", () => {
  const bins = Array.from({ length: 12 }, (_, i) => ({ distance: i === 11 ? 25 : 100, gain: i + 1, loss: 2 }))
  const small = elevationBins(bins)
  const large = elevationBins(bins, true)
  assert.equal(small.at(-1).to - small.at(-1).from, 1.125 - 1.1)
  assert.deepEqual(large.map(sample => [sample.from, sample.to]), [[0, 1], [1, 1.125]])
  for (const key of ["up", "down"]) assert.equal(small.reduce((sum, sample) => sum + sample[key], 0), large.reduce((sum, sample) => sum + sample[key], 0))
  assert.equal(large[0].up, 55)
  assert.equal(large[0].down, 20)
})

test("missing elevation is explicit and aggregation preserves known changes", () => {
  const bins = [{ distance: 100, gain: 5, loss: 3 }, { distance: 100, gain: null, loss: null, missing: true }]
  assert.equal(elevationBins(bins)[1].up, null)
  assert(elevationBins(bins)[1].lines.includes("Elevation missing"))
  const combined = elevationBins(bins, true)[0]
  assert.equal(combined.up, 5)
  assert.equal(combined.down, 3)
  assert(combined.lines.includes("Some elevation missing; known changes only"))
  assert.equal(elevationBins([{ distance: 25, gain: 0, loss: 0 }])[0].to, 0.025)
})
