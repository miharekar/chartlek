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

const { DAY, dayIndexAt, pathAt, hoverAt, catchUpOpacity, catchUpLine, yMax } = await import("helpers/goal_progress")

const start = Date.UTC(2026, 9, 1)
const behind = { start, days: 31, goal_km: 155, cumulative: [5, 5, 5, 20], catch_up: { ratio: 2 } }

test("dayIndexAt snaps to the nearest day and clamps to the period", () => {
  assert.equal(dayIndexAt(start + 0.4 * DAY, start, 31), 0)
  assert.equal(dayIndexAt(start + 2.6 * DAY, start, 31), 3)
  assert.equal(dayIndexAt(start - 5 * DAY, start, 31), 0)
  assert.equal(dayIndexAt(start + 99 * DAY, start, 31), 30)
})

test("pathAt is the goal share through the end of the day", () => {
  assert.equal(pathAt(155, 31, 0), 5)
  assert.equal(pathAt(155, 31, 30), 155)
})

test("hoverAt on a past day gives where you were against the path", () => {
  const hover = hoverAt(behind, 3)

  assert.equal(hover.past, true)
  assert.equal(hover.done, 20)
  assert.equal(hover.path, 20)
  assert.equal(hover.delta, 0)
  assert.equal(hover.required, 135 / 28)

  const earlier = hoverAt(behind, 1)
  assert.equal(earlier.delta, -5)
  assert.equal(earlier.required, null)
})

test("hoverAt on a future day gives the average needed from then on", () => {
  const hover = hoverAt(behind, 20)

  assert.equal(hover.past, false)
  assert.equal(hover.done, null)
  assert.equal(hover.required, 135 / 11)
  assert.equal(hover.remaining, 135)
})

test("hoverAt needs nothing once the goal is reached, and works before the period starts", () => {
  assert.equal(hoverAt({ days: 31, goal_km: 10, cumulative: [12] }, 5).required, 0)
  assert.equal(hoverAt({ days: 31, goal_km: 31, cumulative: [] }, 0).required, 1)
})

test("hoverAt on an ended period shows no required rate, even on the last day", () => {
  const ended = { days: 3, goal_km: 30, cumulative: [10, 15, 18], ended: true }
  const last = hoverAt(ended, 2)

  assert.equal(last.required, null)
  assert.equal(last.done, 18)
  assert.equal(last.remaining, 12)
  assert.equal(hoverAt(ended, 0).required, null)
})

test("hoverAt compares today with yesterday's path until today has a run", () => {
  const open = { days: 31, goal_km: 155, cumulative: [5, 10, 15], open_today: true }

  assert.equal(hoverAt(open, 2).path, 10)
  assert.equal(hoverAt(open, 2).delta, 5)
  assert.equal(hoverAt(open, 1).path, 10)
  assert.equal(hoverAt({ ...open, open_today: false }, 2).path, 15)
  assert.equal(hoverAt({ days: 31, goal_km: 155, cumulative: [5], open_today: true }, 0).path, 0)
})

test("catchUpOpacity grows with the ratio and is solid without a recent average", () => {
  assert.equal(catchUpOpacity(null), 1)
  assert.equal(catchUpOpacity(0.5), 0.35)
  assert.equal(catchUpOpacity(2), 0.675)
  assert.equal(catchUpOpacity(9), 1)
})

test("catchUpLine runs from today's total to the goal only when behind", () => {
  assert.deepEqual(catchUpLine(behind), [[3, 20], [30, 155]])
  assert.equal(catchUpLine({ ...behind, catch_up: null }), null)
})

test("yMax covers the goal and an overshoot", () => {
  assert.equal(yMax(behind), 155)
  assert.equal(yMax({ goal_km: 10, cumulative: [12] }), 12)
})
