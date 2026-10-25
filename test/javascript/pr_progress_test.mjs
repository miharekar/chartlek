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

const { parseRuns, windowBest, daysSince, daysSincePr, percentSlower, recordsByBucket, predictions, subLabel, magicText } = await import("helpers/pr_progress")

const day = number => Date.UTC(2024, 0, number)
const run = (id, date, bucket, best) => ({ id, time: date + 7 * 3600000, bucket, best })

const runs = [run(1, day(1), 5, 3100), run(2, day(3), 5, 3000), run(3, day(4), null, null), run(4, day(6), 5, 2950), run(5, day(8), 2, 1500), run(6, day(10), 5, 3050)]

test("parseRuns zips columns with rows", () => {
  const parsed = parseRuns({ columns: ["id", "name"], runs: [[1, "a"], [2, "b"]] })

  assert.deepEqual(parsed, [{ id: 1, name: "a" }, { id: 2, name: "b" }])
})

test("windowBest takes the fastest run per bucket inside the window", () => {
  const best = windowBest(runs, [day(2), day(9)], 14)

  assert.equal(best[5].id, 4)
  assert.equal(best[2].id, 5)
  assert.equal(best.filter(Boolean).length, 2)
})

test("windowBest treats the end as exclusive and ignores runs without a bucket", () => {
  assert.equal(windowBest(runs, [day(2), day(6)], 14)[5].id, 2)
  assert.equal(windowBest(runs, [day(2), day(6) + 8 * 3600000], 14)[5].id, 4)
  assert.equal(windowBest(runs, [day(4), day(5)], 14).filter(Boolean).length, 0)
})

test("windowBest is empty for a window without runs", () => {
  assert.equal(windowBest(runs, [day(20), day(30)], 14).filter(Boolean).length, 0)
})

test("daysSince counts from the last day of the window and ignores later runs", () => {
  const since = daysSince(runs, day(9), 14)

  assert.equal(since[5], 2)
  assert.equal(since[2], 0)
  assert.equal(since[0], undefined)
})

test("daysSince looks back past the window start and never forward", () => {
  const since = daysSince(runs, day(3), 14)

  assert.equal(since[5], 1)
  assert.equal(since[2], undefined)
})

test("daysSincePr counts from the best performance up to the window end", () => {
  assert.equal(daysSincePr(runs, day(5), 14)[5], 1)
  assert.equal(daysSincePr(runs, day(7), 14)[5], 0)
  assert.equal(daysSincePr(runs, day(12), 14)[5], 5)
})

test("daysSincePr ignores later runs and distances without a run", () => {
  const since = daysSincePr(runs, day(2), 14)

  assert.equal(since[5], 0)
  assert.equal(since[2], undefined)
  assert.equal(since[0], undefined)
})

test("percentSlower", () => {
  assert.equal(percentSlower(1100, 1000), 10)
  assert.equal(percentSlower(1000, 1000), 0)
})

test("predictions compare against the PR per bucket", () => {
  const table = [[1, 4000], [500, 3000], [1000, 2000]]
  const benchmarks = [{ meters: 10000, table }, { meters: 5000, table }, { meters: 3000, table }]
  const records = recordsByBucket([{ bucket: 0, time: 3200 }, { bucket: 1, time: 2900 }], 3)

  const result = predictions(benchmarks, records, 500)

  assert.equal(result[0].time, 3000)
  assert.equal(result[0].pace, 300)
  assert.equal(result[0].beats, true)
  assert.equal(result[0].change, 6.25)
  assert.equal(result[1].beats, false)
  assert.ok(result[1].change < 0)
  assert.equal(result[2].change, null)
  assert.equal(result[2].beats, true)
})

test("subLabel and magicText", () => {
  assert.equal(subLabel(11700), "3:15")
  assert.equal(subLabel(5700), "1:35")
  assert.equal(subLabel(1440), "24")
  assert.equal(magicText("Marathon", 11700, 12032, (332 / 12032) * 100), "Sub-3:15 marathon: shave 5:32 (2.8%)")
})
