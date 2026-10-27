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

const { seriesColor, initialHidden, toggled, cumulative, stackRows, monthRows } = await import("helpers/gear_charts")

const gears = [
  { id: "g1", retired: false, km: [10, 0, 5] },
  { id: "g2", retired: true, km: [0, 20, 0] }
]

test("retired gear starts hidden and toggling is pure", () => {
  const hidden = initialHidden(gears)
  assert.deepEqual([...hidden], ["g2"])

  const shown = toggled(hidden, "g2")
  assert.equal(shown.size, 0)
  assert.equal(hidden.size, 1)
  assert.deepEqual([...toggled(shown, "g1")], ["g1"])
})

test("cumulative starts the month before first use and carries forward", () => {
  assert.deepEqual(cumulative([10, 0, 5]), [10, 10, 15])
  assert.deepEqual(cumulative([0, 0, 4, 1]), [null, 0, 4, 5])
  assert.deepEqual(cumulative([0, 0]), [null, null])
})

test("stack rows hold one value per gear per month", () => {
  assert.deepEqual(stackRows(["a", "b", "c"], gears)[1], { month: "b", g1: 0, g2: 20 })
})

test("month rows keep only gear used that month", () => {
  assert.deepEqual(monthRows(gears, 1).map(([gear, km]) => [gear.id, km]), [["g2", 20]])
  assert.deepEqual(monthRows(gears, 0).map(([gear]) => gear.id), ["g1"])
})

test("series colours differ per index", () => {
  assert.notEqual(seriesColor(0), seriesColor(1))
  assert.equal(seriesColor(3), seriesColor(3))
})
