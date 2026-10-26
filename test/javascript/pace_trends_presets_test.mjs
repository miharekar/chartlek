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

const { presetWindow, activePreset, PRESETS } = await import("helpers/pace_trends_presets")

const utc = (y, m, d) => new Date(Date.UTC(y, m - 1, d))
const iso = range => range.map(date => date.toISOString().slice(0, 10))
const domain = [utc(2015, 3, 3), utc(2026, 10, 26)]

test("presets end after today and start the span earlier", () => {
  assert.deepEqual(iso(presetWindow(3, domain)), ["2026-07-26", "2026-10-27"])
  assert.deepEqual(iso(presetWindow(6, domain)), ["2026-04-26", "2026-10-27"])
  assert.deepEqual(iso(presetWindow(12, domain)), ["2025-10-26", "2026-10-27"])
  assert.deepEqual(iso(presetWindow(24, domain)), ["2024-10-26", "2026-10-27"])
})

test("all time spans the first run to the end of today", () => {
  assert.deepEqual(iso(presetWindow(null, domain)), ["2015-03-03", "2026-10-27"])
})

test("month ends clamp like Rails and crossing a year works", () => {
  assert.deepEqual(iso(presetWindow(3, [utc(2015, 1, 1), utc(2026, 5, 31)])), ["2026-02-28", "2026-06-01"])
  assert.deepEqual(iso(presetWindow(12, [utc(2015, 1, 1), utc(2024, 2, 29)])), ["2023-02-28", "2024-03-01"])
  assert.deepEqual(iso(presetWindow(3, [utc(2015, 1, 1), utc(2026, 1, 15)])), ["2025-10-15", "2026-01-16"])
  assert.deepEqual(iso(presetWindow(6, [utc(2015, 1, 1), utc(2026, 12, 31)])), ["2026-06-30", "2027-01-01"])
})

test("a span longer than the history clamps to the first run", () => {
  const short = [utc(2026, 1, 10), utc(2026, 10, 26)]

  assert.deepEqual(iso(presetWindow(24, short)), ["2026-01-10", "2026-10-27"])
})

test("the active preset is the one whose window the range equals exactly", () => {
  for (const { key, months } of PRESETS) {
    assert.equal(activePreset(presetWindow(months, domain), domain), key)
  }
  assert.equal(activePreset([utc(2025, 10, 26), utc(2026, 10, 27)].map(Number), domain), "12")
})

test("a dragged range matches no preset", () => {
  assert.equal(activePreset([utc(2025, 10, 27), utc(2026, 10, 27)], domain), undefined)
  assert.equal(activePreset([utc(2025, 10, 26), utc(2026, 10, 20)], domain), undefined)
})

test("when two presets give the same window the longer one is active", () => {
  const short = [utc(2026, 1, 10), utc(2026, 10, 26)]

  assert.equal(activePreset(presetWindow(24, short), short), "all")
  assert.equal(activePreset(presetWindow(12, short), short), "all")
  assert.equal(activePreset(presetWindow(6, short), short), "6")
})
