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

const { formatChange, formatFinishDelta } = await import("helpers/pace_trends_format")

test("formatChange keeps two decimals for small VDOT changes", () => {
  assert.equal(formatChange(0.64), "+0.64/week")
  assert.equal(formatChange(-1.26), "-1.26/week")
  assert.equal(formatChange(0.054), "+0.05/week")
  assert.equal(formatChange(-0.001), "0.00/week")
})

test("formatFinishDelta says Cut or Added", () => {
  assert.deepEqual(formatFinishDelta(2068), { verb: "Cut", time: "34:28" })
  assert.deepEqual(formatFinishDelta(-65), { verb: "Added", time: "1:05" })
  assert.deepEqual(formatFinishDelta(0), { verb: "Cut", time: "0:00" })
})
