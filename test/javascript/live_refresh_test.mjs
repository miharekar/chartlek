import test from "node:test"
import assert from "node:assert/strict"
import { linkStep, shouldRefresh, timeAgoWords } from "../../app/javascript/helpers/live_refresh.js"

test("the first connect is not a reconnect, a drop then a connect is", () => {
  let link = { seen: false, dropped: false }
  const step = connected => {
    const { refresh, ...next } = linkStep(link, connected)
    link = next
    return refresh
  }
  assert.equal(step(false), false)
  assert.equal(step(true), false)
  assert.equal(step(true), false)
  assert.equal(step(false), false)
  assert.equal(step(false), false)
  assert.equal(step(true), true)
  assert.equal(step(true), false)
})

test("a reconnect refreshes unless a form is on the page", () => {
  assert.equal(shouldRefresh(true, false), true)
  assert.equal(shouldRefresh(true, true), false)
  assert.equal(shouldRefresh(false, false), false)
})

test("relative time wording matches time_ago_in_words", () => {
  const words = minutes => timeAgoWords(minutes * 60)
  assert.equal(timeAgoWords(10), "less than a minute")
  assert.equal(words(1), "1 minute")
  assert.equal(words(12), "12 minutes")
  assert.equal(words(44), "44 minutes")
  assert.equal(words(45), "about 1 hour")
  assert.equal(words(90), "about 2 hours")
  assert.equal(words(1439), "about 24 hours")
  assert.equal(words(1440), "1 day")
  assert.equal(words(2520), "2 days")
  assert.equal(words(43199), "30 days")
  assert.equal(words(43200), null)
  assert.equal(timeAgoWords(-5), "less than a minute")
})
