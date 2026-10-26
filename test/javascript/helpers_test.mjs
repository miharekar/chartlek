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

const { formatPace, formatDuration, formatDistance, formatDate } = await import("helpers/formatters")
const { parseTime, snapToDays } = await import("helpers/time")
const { escapeHtml, anchoredPosition, isTooltipFor, showTooltip, showTooltipFor, hideTooltip } = await import("helpers/tooltip")
const { paceScale } = await import("helpers/pace_scale")

test("formatPace", () => {
  assert.equal(formatPace(374), "6:14")
  assert.equal(formatPace(359.6), "6:00")
  assert.equal(formatPace(300), "5:00")
  assert.equal(formatPace(605), "10:05")
  assert.equal(formatPace(59.5), "1:00")
})

test("formatDuration", () => {
  assert.equal(formatDuration(1463), "24:23")
  assert.equal(formatDuration(5850), "1:37:30")
  assert.equal(formatDuration(3599.6), "1:00:00")
  assert.equal(formatDuration(59), "0:59")
  assert.equal(formatDuration(3599.5), "1:00:00")
  assert.equal(formatDuration(59.5), "1:00")
})

test("formatDistance", () => {
  assert.equal(formatDistance(12.34), "12.3")
  assert.equal(formatDistance(5), "5.0")
})

test("parseTime reads epoch milliseconds and ISO strings as UTC", () => {
  const expected = Date.UTC(2020, 3, 21, 23, 30)
  assert.equal(+parseTime(expected), expected)
  assert.equal(+parseTime("2020-04-21T23:30:00.000Z"), expected)
  assert.equal(+parseTime("2020-04-21"), Date.UTC(2020, 3, 21))
})

test("formatDate uses UTC wall clock", () => {
  assert.equal(formatDate(Date.UTC(2020, 3, 21, 23, 59)), "21 Apr 2020")
  assert.equal(formatDate("2021-01-01T00:00:00Z"), "1 Jan 2021")
})

test("paceScale is linear in speed with faster paces first", () => {
  const scale = paceScale([240, 600], [0, 300])
  assert.equal(scale(240), 0)
  assert.ok(Math.abs(scale(600) - 300) < 1e-9)
  assert.ok(scale(300) < scale(360))
  const midSpeed = 2 / (1 / 240 + 1 / 600)
  assert.ok(Math.abs(scale(midSpeed) - 150) < 1e-9)
  assert.ok(Math.abs(scale.invert(scale(450)) - 450) < 1e-9)
})

test("paceScale ticks are evenly spaced speeds labeled as pace", () => {
  const scale = paceScale([257, 1800], [0, 1000])
  const ticks = scale.ticks()
  const speeds = ticks.map(pace => Math.round(3600 / pace))
  assert.deepEqual(speeds, [14, 12, 10, 8, 6, 4, 2])
  assert.deepEqual(ticks.map(scale.tickFormat()), ["4:17", "5:00", "6:00", "7:30", "10:00", "15:00", "30:00"])
  const positions = ticks.map(scale)
  const gaps = positions.slice(1).map((position, index) => position - positions[index])
  assert.ok(gaps.every(gap => Math.abs(gap - gaps[0]) < 1e-6))
})

test("paceScale ticks skip zero speed", () => {
  const ticks = paceScale([300, 36000], [0, 100]).ticks(20)
  assert.ok(ticks.every(pace => Number.isFinite(pace) && pace > 0))
})

test("paceScale copy is an equivalent scale", () => {
  const scale = paceScale([240, 600], [0, 300])
  const copy = scale.copy()
  assert.notEqual(copy, scale)
  assert.deepEqual(copy.domain(), scale.domain())
  assert.deepEqual(copy.range(), scale.range())
  assert.equal(copy(420), scale(420))
  assert.deepEqual(copy.ticks(), scale.ticks())
})

test("snapToDays aligns to UTC midnight", () => {
  const [start, end] = snapToDays([Date.UTC(2020, 3, 21, 5), Date.UTC(2020, 3, 25, 13)].map(parseTime))
  assert.equal(+start, Date.UTC(2020, 3, 21))
  assert.equal(+end, Date.UTC(2020, 3, 26))
})

test("snapToDays spans at least one day", () => {
  const [start, end] = snapToDays([new Date(Date.UTC(2020, 3, 21, 2)), new Date(Date.UTC(2020, 3, 21, 9))])
  assert.equal(+start, Date.UTC(2020, 3, 21))
  assert.equal(+end, Date.UTC(2020, 3, 22))
})

test("snapToDays rounds near midnight UTC", () => {
  const [start, end] = snapToDays([new Date(Date.UTC(2020, 3, 21, 23, 59)), new Date(Date.UTC(2020, 3, 24, 0, 1))])
  assert.equal(+start, Date.UTC(2020, 3, 22))
  assert.equal(+end, Date.UTC(2020, 3, 24))
})

test("snapToDays keeps the range inside the bounds", () => {
  const bounds = [new Date(Date.UTC(2020, 0, 1)), new Date(Date.UTC(2020, 0, 11))]
  const [start, end] = snapToDays([new Date(Date.UTC(2020, 0, 10, 20)), new Date(Date.UTC(2020, 0, 11, 1))], bounds)
  assert.equal(+start, Date.UTC(2020, 0, 10))
  assert.equal(+end, Date.UTC(2020, 0, 11))
})

test("snapToDays clamps a wide range to the bounds", () => {
  const bounds = [new Date(Date.UTC(2020, 2, 1)), new Date(Date.UTC(2020, 2, 15))]
  const day = (month, date) => new Date(Date.UTC(2020, month, date))
  assert.deepEqual(snapToDays([day(2, 5), day(2, 20)], bounds), [day(2, 5), day(2, 15)])
  assert.deepEqual(snapToDays([day(1, 1), day(2, 10)], bounds), [day(2, 1), day(2, 10)])
  assert.deepEqual(snapToDays([day(1, 1), day(2, 20)], bounds), bounds)
  assert.deepEqual(snapToDays([day(3, 1), day(3, 5)], bounds), [day(2, 14), day(2, 15)])
  assert.deepEqual(snapToDays([day(0, 1), day(0, 5)], bounds), [day(2, 1), day(2, 2)])
})

test("escapeHtml escapes markup characters", () => {
  assert.equal(escapeHtml(`Run <3 & "fun" 'ok'`), "Run &lt;3 &amp; &quot;fun&quot; &#39;ok&#39;")
  assert.equal(escapeHtml(5), "5")
})

test("anchoredPosition", () => {
  const viewport = { width: 400, height: 600 }
  const size = { width: 200, height: 60 }
  const anchor = (left, top) => ({ left, top, width: 16, height: 16, bottom: top + 16 })

  assert.deepEqual(anchoredPosition(anchor(100, 100), size, viewport), { left: 8, top: 122 })
  assert.deepEqual(anchoredPosition(anchor(180, 100), size, viewport), { left: 88, top: 122 })
  assert.equal(anchoredPosition(anchor(390, 100), size, viewport).left, 192)
  assert.equal(anchoredPosition(anchor(180, 560), size, viewport).top, 494)
})

test("the tooltip knows which anchor it is showing for", () => {
  const classes = new Set(["hidden"])
  const tooltip = { className: "", style: {}, isConnected: true, classList: { add: name => classes.add(name), remove: name => classes.delete(name), contains: name => classes.has(name) }, getBoundingClientRect: () => ({ width: 100, height: 20 }) }
  globalThis.document = { createElement: () => tooltip, body: { append() {} } }
  globalThis.window = { innerWidth: 400, innerHeight: 600 }
  const anchor = { getBoundingClientRect: () => ({ left: 10, top: 10, width: 16, height: 16, bottom: 26 }) }
  const other = { getBoundingClientRect: anchor.getBoundingClientRect }

  try {
    assert.equal(isTooltipFor(anchor), false)
    showTooltipFor("a", anchor)
    assert.equal(isTooltipFor(anchor), true)
    assert.equal(isTooltipFor(other), false)
    showTooltip("chart", { clientX: 5, clientY: 5 })
    assert.equal(isTooltipFor(anchor), false)
    showTooltipFor("a", anchor)
    hideTooltip()
    assert.equal(isTooltipFor(anchor), false)
  } finally {
    delete globalThis.document
    delete globalThis.window
  }
})
