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

const { seriesColor, initialHidden, toggled, cumulative, stackRows, monthRows, visibleSpan, zoom, monthTicks, barTicks } = await import("helpers/gear_charts")

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

const months = ["m0", "m1", "m2", "m3", "m4", "m5"]
const old = { id: "a", km: [5, 5, 0, 0, 0, 0] }
const recent = { id: "b", km: [0, 0, 0, 7, 0, 3] }
const later = { id: "c", km: [0, 0, 0, 0, 2, 0] }

test("visible span runs from the first to the last month any visible gear was used", () => {
  assert.deepEqual(visibleSpan([recent]), [3, 5])
  assert.deepEqual(visibleSpan([old, recent]), [0, 5])
  assert.deepEqual(visibleSpan([{ id: "x", km: [0, 0] }]), null)
  assert.equal(visibleSpan([]), null)
})

test("zoom slices months and every gear to the visible span", () => {
  const zoomed = zoom(months, [recent, later])

  assert.deepEqual(zoomed.months, ["m3", "m4", "m5"])
  assert.deepEqual(zoomed.gears.map(gear => gear.km), [[7, 0, 3], [0, 2, 0]])
  assert.deepEqual(recent.km, [0, 0, 0, 7, 0, 3])
})

test("zoom keeps gaps between used months", () => {
  assert.deepEqual(zoom(months, [old, later]).months, months.slice(0, 5))
})

test("a lead month is kept for the cumulative chart but never before the first month", () => {
  assert.deepEqual(zoom(months, [recent], 1).months, ["m2", "m3", "m4", "m5"])
  assert.deepEqual(zoom(months, [old], 1).months, ["m0", "m1"])
})

test("a lead zoom spans at least two months even when use is only in the first month", () => {
  const first = { id: "f", km: [4, 0, 0, 0, 0, 0] }

  assert.deepEqual(zoom(months, [first], 1).months, ["m0", "m1"])
  assert.deepEqual(zoom(months, [first], 1).gears[0].km, [4, 0])
  assert.deepEqual(zoom(months, [first]).months, ["m0"])
  assert.deepEqual(zoom(["m0"], [{ id: "f", km: [4] }], 1).months, ["m0"])
})

test("with nothing visible the full range stays", () => {
  assert.deepEqual(zoom(months, []), { months, gears: [] })
})

test("monthTicks lands on month starts, one per 80 px, clear of the right edge", () => {
  const label = date => (date.getUTCMonth() === 0 ? String(date.getUTCFullYear()) : date.toLocaleString("en", { month: "short", timeZone: "UTC" }))
  const run = (from, count) => Array.from({ length: count }, (_, index) => new Date(Date.UTC(2020, from + index, 1)))

  for (const [from, count] of [[9, 2], [9, 3], [3, 6], [0, 72], [11, 70]]) {
    for (const width of [280, 1236]) {
      const months = run(from, count)
      const ticks = monthTicks(months, width)
      const labels = ticks.map(label)
      const x = date => ((date - months[0]) / (months.at(-1) - months[0])) * width

      assert.ok(ticks.length >= 1 && ticks.length <= Math.max(2, Math.floor(width / 80)), `${count} months at ${width}: ${labels}`)
      assert.ok(ticks.every(date => date.getUTCDate() === 1))
      assert.equal(new Set(ticks.map(date => date.getUTCFullYear() * 12 + date.getUTCMonth())).size, ticks.length)
      assert.ok(ticks.every(date => x(date) <= width - 14), `${count} months at ${width}: ${labels}`)
      labels.forEach((name, index) => assert.notEqual(name, labels[index - 1]))
    }
  }
  assert.deepEqual(monthTicks(run(9, 2), 1236).map(label), ["Oct"])
})

test("barTicks labels each January and the first month only when a year label fits before the next January", () => {
  const run = (from, count) => Array.from({ length: count }, (_, index) => new Date(Date.UTC(2020, from + index, 1)))
  const step = (width, count) => width / count

  assert.deepEqual(barTicks(run(8, 52), step(294, 52)), [4, 16, 28, 40])
  assert.equal(barTicks(run(8, 52), step(1236, 52))[0], 0)
  assert.equal(barTicks(run(0, 52), step(294, 52))[0], 0)
  assert.equal(barTicks(run(2, 52), step(294, 52))[0], 0)
  assert.deepEqual(barTicks(run(11, 64), step(1236, 64)).slice(0, 2), [1, 13])
  assert.deepEqual(barTicks(run(8, 10), 20), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
})
