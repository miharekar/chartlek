import assert from "node:assert/strict"
import { test } from "node:test"

const { rangeStats } = await import(new URL("../../app/javascript/helpers/run_stats.js", import.meta.url))

const bars = [
  { distance: 100, time: 30, hr: 140, cad: 170 },
  { distance: 100, time: 30, hr: 160, cad: 180 },
  { distance: 50, time: 20, hr: null, cad: null }
]

test("rangeStats covers the whole run", () => {
  const stats = rangeStats(bars, 0, 250)
  assert.equal(stats.distance, 250)
  assert.equal(stats.time, 80)
  assert.equal(stats.pace, 320)
  assert.equal(stats.hr, 150)
  assert.equal(stats.cad, 175)
})

test("rangeStats takes the overlapping share of partial bars", () => {
  const stats = rangeStats(bars, 50, 150)
  assert.equal(stats.distance, 100)
  assert.equal(stats.time, 30)
  assert.equal(stats.pace, 300)
  assert.equal(stats.hr, 150)
})

test("rangeStats leaves hr and cadence null without samples", () => {
  const stats = rangeStats(bars, 200, 250)
  assert.equal(stats.hr, null)
  assert.equal(stats.cad, null)
  assert.equal(stats.pace, 400)
})

test("rangeStats of an empty selection has no pace", () => {
  const stats = rangeStats(bars, 300, 400)
  assert.equal(stats.distance, 0)
  assert.equal(stats.pace, null)
})
