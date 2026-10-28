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

const { pointerPosition, tooltipHtml } = await import("helpers/tooltip")

test("tooltipHtml renders a muted title and a label and value grid", () => {
  const html = tooltipHtml("5.5–5.6 km", [["Pace", "5:30 /km"], ["HR", 150]])

  assert(html.includes('<div class="mb-1 text-zinc-500 dark:text-zinc-400">5.5–5.6 km</div>'))
  assert(html.includes('<div class="grid grid-cols-[auto_auto] gap-x-4">'))
  assert(html.includes('<div class="text-zinc-500 dark:text-zinc-400">Pace</div><div class="text-right">5:30 /km</div>'))
  assert(html.includes('<div class="text-right">150</div>'))
  assert(!html.includes("font-medium"))
})

test("tooltipHtml escapes the heading, title, labels and values", () => {
  const html = tooltipHtml('<i>d</i> & "t"', [['<b>L</b>', "<script>alert(1)</script>"]], { heading: "<img src=x onerror=1>" })

  assert(!html.includes("<img"))
  assert(!html.includes("<script"))
  assert(!html.includes("<b>"))
  assert(!html.includes("<i>"))
  assert(html.includes("&lt;img src=x onerror=1&gt;"))
  assert(html.includes("&lt;script&gt;alert(1)&lt;/script&gt;"))
  assert(html.includes("&amp; &quot;t&quot;"))
})

test("tooltipHtml puts an optional heading first and skips falsy rows", () => {
  const html = tooltipHtml("2 Mar 2024", [["Pace", "5:00 /km"], false, null, undefined, ["Time", "25:00"]], { heading: "Morning Run" })

  assert(html.startsWith('<div class="font-medium">Morning Run</div>'))
  assert.equal((html.match(/text-right/g) || []).length, 2)
  assert(!tooltipHtml("t", []).includes("font-medium"))
})

const size = { width: 100, height: 40 }
const viewport = { width: 390, height: 800 }

test("pointerPosition keeps the mouse placement: below right, flipped at the edges", () => {
  assert.deepEqual(pointerPosition({ x: 100, y: 100 }, size, viewport), { left: 114, top: 114 })
  assert.deepEqual(pointerPosition({ x: 380, y: 790 }, size, viewport), { left: 266, top: 736 })
})

test("pointerPosition puts the tooltip above a finger, centred and clamped to the viewport", () => {
  assert.deepEqual(pointerPosition({ x: 200, y: 300 }, size, viewport, true), { left: 150, top: 212 })
  assert.equal(pointerPosition({ x: 5, y: 300 }, size, viewport, true).left, 8)
  assert.equal(pointerPosition({ x: 389, y: 300 }, size, viewport, true).left, 282)
})

test("pointerPosition drops a touch tooltip below the finger when there is no room above", () => {
  assert.equal(pointerPosition({ x: 200, y: 60 }, size, viewport, true).top, 108)
})
