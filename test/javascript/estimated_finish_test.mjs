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

const { finishRow, nextIndex } = await import("helpers/estimated_finish")

test("nextIndex steps 5K, 10K, Half, Marathon and wraps", () => {
  const order = []
  let index = 0
  for (let step = 0; step < 5; step++) {
    order.push(index)
    index = nextIndex(index, 4)
  }
  assert.deepEqual(order, [0, 1, 2, 3, 0])
})

test("finishRow formats time and pace", () => {
  assert.deepEqual(finishRow({ label: "5K", km: 5, seconds: 1196 }), { label: "5K", time: "19:56", pace: "3:59" })
  assert.deepEqual(finishRow({ label: "Marathon", km: 42.195, seconds: 11436 }), { label: "Marathon", time: "3:10:36", pace: "4:31" })
})
