import assert from "node:assert/strict"
import { test } from "node:test"
import { distribution } from "../../app/javascript/helpers/rank_distribution.js"

test("distance bins count every run and highlight the current bucket including ties", () => {
  const bins = distribution([5, 10, 10, 15, 20], 10)
  assert.equal(bins.reduce((sum, bin) => sum + bin.count, 0), 5)
  assert.equal(bins.filter(bin => bin.current).length, 1)
  assert.equal(bins.find(bin => bin.current).count, 2)
  assert.equal(bins.at(-1).count, 2)
  assert.equal(distribution([5, 10, 20], 20).at(-1).current, true)
})

test("single runs and identical paces have a nonzero domain and one highlighted bar", () => {
  for (const values of [[300], [300, 300, 300]]) {
    const bins = distribution(values, 300)
    assert.equal(bins.length, 1)
    assert.equal(bins[0].count, values.length)
    assert(bins[0].current)
    assert(bins[0].from < 300 && bins[0].to > 300)
  }
})

test("small cohorts retain both extremes and empty cohorts draw nothing", () => {
  assert.deepEqual(distribution([], 5), [])
  const bins = distribution([250, 350], 250)
  assert.deepEqual(bins.map(bin => bin.count), [1, 1])
  assert.deepEqual(bins.map(bin => bin.current), [true, false])
})
