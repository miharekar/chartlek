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

const { variabilityWedges, wedgeSummary, centreFontSize } = await import("helpers/pace_variability")
const { rovingTarget, noMouseFocus } = await import("helpers/roving")

const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-9, `${actual} !== ${expected}`)
const bars = times => times.map((time, index) => ({ from: index / 10, to: (index + 1) / 10, distance: 100, time }))

test("one equal-angle wedge per 100 m bar, clockwise from 12 o'clock", () => {
  const wedges = variabilityWedges(bars([30, 15, 30, 15]))

  assert.equal(wedges.length, 4)
  near(wedges[0].start, 0)
  wedges.forEach(wedge => near(wedge.end - wedge.start, Math.PI / 2))
  near(wedges.at(-1).end, 2 * Math.PI)
  wedges.forEach((wedge, index) => { near(wedge.from, index / 10); near(wedge.to, (index + 1) / 10) })
})

test("the radius is the deviation from the mean speed plus a 0.25 base over a 0.75 floor", () => {
  const wedges = variabilityWedges(bars([30, 15]))

  near(wedges[0].deviation, -1 / 3)
  near(wedges[1].deviation, 1 / 3)
  wedges.forEach(wedge => near(wedge.value, 1 / 3 + 0.25))
  wedges.forEach(wedge => near(wedge.ratio, (1 / 3 + 0.25) / 0.75))
  const steady = variabilityWedges(bars([30, 30, 30]))
  steady.forEach(wedge => near(wedge.value, 0.25))
  steady.forEach(wedge => near(wedge.ratio, 1 / 3))
})

test("the domain grows past 0.75 for a big swing and ratios stay within 1", () => {
  const wedges = variabilityWedges(bars([30, 30, 30, 30, 30, 30, 30, 30, 3]))

  assert.ok(Math.max(...wedges.map(wedge => wedge.value)) > 0.75)
  near(Math.max(...wedges.map(wedge => wedge.ratio)), 1)
  assert.ok(wedges.every(wedge => wedge.ratio > 0 && wedge.ratio <= 1))
})

test("wedges take their labels from the bars, so a gap in the bars does not shift later ones", () => {
  const wedges = variabilityWedges([
    { from: 0, to: 0.1, distance: 100, time: 30 },
    { from: 0.2, to: 0.3, distance: 100, time: 15 },
    { from: 0.3, to: 0.4, distance: 100, time: 30 }
  ])

  assert.deepEqual(wedges.map(wedge => [wedge.from, wedge.to]), [[0, 0.1], [0.2, 0.3], [0.3, 0.4]])
  assert.equal(wedgeSummary(wedges[1]).title, "0.2–0.3 km")
  assert.equal(variabilityWedges(bars(Array(422).fill(30))).length, 422)
})

test("fewer than two whole bars or no movement give no wedges", () => {
  assert.deepEqual(variabilityWedges([]), [])
  assert.deepEqual(variabilityWedges(bars([30])), [])
})

test("the order of the bars changes the picture", () => {
  assert.notDeepEqual(variabilityWedges(bars([20, 40, 20, 40])).map(w => w.deviation), variabilityWedges(bars([20, 20, 40, 40])).map(w => w.deviation))
})

test("the summary gives the distance range, the pace and the signed deviation", () => {
  const [slow, fast] = variabilityWedges(bars([30, 15])).map(wedgeSummary)

  assert.equal(slow.title, "0.0–0.1 km")
  assert.deepEqual(slow.rows, [["Pace", "5:00 /km"], ["Speed vs average", "-33.3%"]])
  assert.deepEqual(fast.rows, [["Pace", "2:30 /km"], ["Speed vs average", "+33.3%"]])
  assert.equal(fast.label, "0.1–0.2 km. Pace 2:30 /km. Speed vs average +33.3%")
})

test("the centre number is sized to fit the hole", () => {
  const hole = 60

  assert.ok(centreFontSize("18.0%", hole) <= hole * 0.62)
  assert.ok(centreFontSize("100.0%", hole) < centreFontSize("8.0%", hole))
  const width = text => centreFontSize(text, hole) * text.length * 0.6
  assert.ok(width("100.0%") <= hole * 1.64 + 1e-9)
  assert.ok(width("18.0%") <= hole * 1.64 + 1e-9)
})

test("roving keys move by one, jump to the ends and clamp", () => {
  assert.equal(rovingTarget("ArrowRight", 2, 9), 3)
  assert.equal(rovingTarget("ArrowLeft", 2, 9), 1)
  assert.equal(rovingTarget("ArrowRight", 9, 9), 9)
  assert.equal(rovingTarget("ArrowLeft", 0, 9), 0)
  assert.equal(rovingTarget("Home", 5, 9), 0)
  assert.equal(rovingTarget("End", 5, 9), 9)
  assert.equal(rovingTarget("Tab", 5, 9), null)
  assert.equal(rovingTarget("ArrowUp", 5, 9), null)
})

test("noMouseFocus stops the default mousedown focus and blurs a focused element of the same chart", () => {
  let prevented = 0
  let blurred = 0
  const focused = { blur: () => blurred++ }
  const chart = { contains: node => node === focused }
  const target = { closest: () => chart }
  globalThis.document = { activeElement: focused }

  noMouseFocus({ preventDefault: () => prevented++, currentTarget: target })

  assert.equal(prevented, 1)
  assert.equal(blurred, 1)
})

test("noMouseFocus leaves focus elsewhere on the page alone", () => {
  let blurred = 0
  const elsewhere = { blur: () => blurred++ }
  const chart = { contains: () => false }
  globalThis.document = { activeElement: elsewhere }

  noMouseFocus({ preventDefault: () => {}, currentTarget: { closest: () => chart } })
  globalThis.document = { activeElement: null }
  noMouseFocus({ preventDefault: () => {}, currentTarget: { closest: () => null } })

  assert.equal(blurred, 0)
  delete globalThis.document
})
