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

const { elevationBins } = await import("helpers/recording_bars")

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
  assert.deepEqual(elevationBins(bins)[1].rows, [["Elevation", "missing"]])
  const combined = elevationBins(bins, true)[0]
  assert.equal(combined.up, 5)
  assert.equal(combined.down, 3)
  assert.deepEqual(combined.rows, [["Gained", "5.0 m"], ["Lost", "3.0 m"], ["Note", "some elevation missing"]])
  assert.equal(elevationBins([{ distance: 25, gain: 0, loss: 0 }])[0].to, 0.025)
})

test("elevation tooltip ranges use one decimal like the speed chart", () => {
  const bins = Array.from({ length: 60 }, () => ({ distance: 100, gain: 1.25, loss: 0.5 }))

  assert.equal(elevationBins(bins)[55].title, "5.5–5.6 km")
  assert.equal(elevationBins(bins, true)[5].title, "5.0–6.0 km")
  assert.equal(elevationBins(bins)[0].title, "0.0–0.1 km")
  assert.deepEqual(elevationBins(bins)[55].rows, [["Gained", "1.3 m"], ["Lost", "0.5 m"]])
  assert.equal(elevationBins(bins)[55].label, "5.5–5.6 km. Gained 1.3 m. Lost 0.5 m")
})

test("a short last bin whose ends round alike reads as one value", () => {
  const bins = [...Array.from({ length: 54 }, () => ({ distance: 100, gain: 1, loss: 1 })), { distance: 25, gain: 0.2, loss: 0 }]
  const small = elevationBins(bins)

  assert.equal(small.at(-1).title, "5.4 km")
  assert.equal(small.at(-1).label, "5.4 km. Gained 0.2 m. Lost 0.0 m")
  assert.equal(small.at(-2).title, "5.3–5.4 km")
  assert.equal(elevationBins(bins, true).at(-1).title, "5.0–5.4 km")
})
