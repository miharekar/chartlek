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

const cohort = () => [...Array.from({ length: 300 }, (_, i) => 250 + (i % 60) * 4), ...Array.from({ length: 6 }, (_, i) => 1000 + i * 100), 200, 210]

test("an outlier-heavy cohort bins over the 2nd to 98th percentile and folds the tails into open-ended edge bins", () => {
  const values = cohort()
  const bins = distribution(values, 300)

  assert.equal(bins.reduce((sum, bin) => sum + bin.count, 0), values.length)
  assert(bins.at(-1).to < 600)
  assert(bins[0].from >= 200)
  assert.equal(bins[0].open, "below")
  assert.equal(bins.at(-1).open, "above")
  assert(bins.slice(1, -1).every(bin => bin.open === undefined))
  assert(bins.slice(1, -1).every(bin => bin.count > 10))
  assert.equal(bins.filter(bin => bin.current).length, 1)
})

test("a current run past the domain highlights the matching edge bin", () => {
  const bins = distribution(cohort(), 1500)

  assert.equal(bins.at(-1).current, true)
  assert.equal(bins.filter(bin => bin.current).length, 1)
  assert.equal(distribution(cohort(), 100)[0].current, true)
})

test("no edge bin is open-ended when nothing lies outside the trimmed domain", () => {
  const bins = distribution(Array.from({ length: 100 }, () => 300), 300)

  assert.equal(bins.length, 1)
  assert(bins.every(bin => bin.open === undefined))
})

test("cohorts under 20 runs keep the full range", () => {
  const values = [250, 260, 270, 280, 290, 300, 310, 320, 330, 1500]
  const bins = distribution(values, 250)

  assert.equal(bins.at(-1).to, 1500)
  assert(bins.every(bin => bin.open === undefined))
})

test("both edges trim the same number of runs from 26 runs up", () => {
  const body = Array.from({ length: 24 }, (_, i) => 250 + i * 2)
  const one = distribution([...body, 100, 1000], 260)
  const two = distribution([...body, 1000, 1100], 260)

  assert.equal(one.at(-1).open, "above")
  assert(one.at(-1).from < 400)
  assert.equal(one[0].open, "below")
  assert.equal(two.at(-1).open, "above")
  assert.equal(two[0].open, "below")
  assert.equal(two.at(-1).to, 1000)
  assert.equal(two.reduce((sum, bin) => sum + bin.count, 0), 26)
})

test("25 runs or fewer are not trimmed", () => {
  const bins = distribution([...Array.from({ length: 24 }, (_, i) => 250 + i * 2), 1000], 260)

  assert.equal(bins.at(-1).to, 1000)
  assert(bins.every(bin => bin.open === undefined))
})

test("a collapsed trimmed range still flags the folded outliers", () => {
  const bins = distribution([...Array(40).fill(300), 100, 900], 300)

  assert(bins.length > 1)
  assert.equal(bins[0].open, "below")
  assert.equal(bins.at(-1).open, "above")
  assert.equal(bins.reduce((sum, bin) => sum + bin.count, 0), 42)
  assert.equal(bins.find(bin => bin.current).count, 40)
})

test("a current run inside the trimmed tail extends the domain to the real maximum", () => {
  const bins = distribution(cohort(), 1200)

  assert.equal(bins.at(-1).to, 1500)
  assert.equal(bins.at(-1).open, undefined)
  assert.equal(bins[0].open, "below")
  assert.equal(bins.filter(bin => bin.current).length, 1)
  assert.equal(bins.find(bin => bin.current).to > 1200, true)
  assert.equal(bins.find(bin => bin.current).from <= 1200, true)
  assert.equal(bins.at(-1).current, false)
  assert.equal(bins.reduce((sum, bin) => sum + bin.count, 0), cohort().length)
})

test("a current run inside the low trimmed tail extends the domain to the real minimum", () => {
  const bins = distribution(cohort(), 205)

  assert.equal(bins[0].from, 200)
  assert.equal(bins[0].open, undefined)
  assert.equal(bins.at(-1).open, "above")
  assert.equal(bins.filter(bin => bin.current).length, 1)
  assert.equal(bins.find(bin => bin.current).from <= 205, true)
  assert.equal(bins.find(bin => bin.current).to > 205, true)
  assert.equal(bins[0].current, true)
})
