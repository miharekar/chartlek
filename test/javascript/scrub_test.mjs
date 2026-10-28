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

const { isTouch, scrub } = await import("helpers/scrub")

function fakeSelection() {
  const owner = { style: {} }
  const selection = { owner, handlers: {} }
  selection.each = callback => { callback.call({ ownerSVGElement: owner, style: {} }); return selection }
  selection.on = (type, handler) => { selection.handlers[type] = handler; return selection }
  return selection
}

const touch = { pointerType: "touch", pointerId: 7 }
const mouse = { pointerType: "mouse", pointerId: 1 }

test("isTouch only matches touch pointers", () => {
  assert(isTouch(touch))
  assert(!isTouch(mouse))
  assert(!isTouch({}))
})

test("surface mode sets pan-y pinch-zoom on the owning svg (SVG shapes ignore touch-action), reports a touch press as a move and passes the rest through", () => {
  const calls = []
  const selection = fakeSelection()
  const move = event => calls.push(["move", event.pointerType])
  const leave = () => calls.push(["leave"])
  scrub(selection, { move, leave })

  assert.equal(selection.owner.style.touchAction, "pan-y pinch-zoom")
  selection.handlers["pointerdown.scrub"].call({}, touch)
  selection.handlers["pointerdown.scrub"].call({}, mouse)
  assert.equal(selection.handlers["pointermove.scrub"], move)
  assert.equal(selection.handlers["pointerleave.scrub"], leave)
  assert.deepEqual(calls, [["move", "touch"]])
})

test("items mode releases the implicit touch capture so the finger enters the items it crosses", () => {
  const released = []
  const selection = fakeSelection()
  scrub(selection, { mode: "items", enter() {}, move() {}, leave() {} })
  const target = { releasePointerCapture: id => released.push(id) }

  selection.handlers["pointerdown.scrub"].call({}, { ...touch, target })
  selection.handlers["pointerdown.scrub"].call({}, { ...mouse, target })
  assert.deepEqual(released, [7])
})

test("tap mode leaves touch-action alone, moves on a touch press and treats a touch drag as leaving", () => {
  const calls = []
  const selection = fakeSelection()
  scrub(selection, { mode: "tap", move: event => calls.push(["move", event.pointerType]), leave: event => calls.push(["leave", event.pointerType]) })

  assert.equal(selection.owner.style.touchAction, undefined)
  selection.handlers["pointerdown.scrub"].call({}, touch)
  selection.handlers["pointermove.scrub"].call({}, touch)
  selection.handlers["pointermove.scrub"].call({}, mouse)
  selection.handlers["pointerleave.scrub"].call({}, touch)
  selection.handlers["pointerleave.scrub"].call({}, mouse)
  assert.deepEqual(calls, [["move", "touch"], ["leave", "touch"], ["move", "mouse"], ["leave", "mouse"]])
})

test("tap mode clears on pointercancel (a scroll took the touch); other modes leave that to pointerleave", () => {
  const leave = () => {}
  const tap = fakeSelection()
  scrub(tap, { mode: "tap", leave })
  const surface = fakeSelection()
  scrub(surface, { leave })

  assert.equal(tap.handlers["pointercancel.scrub"], leave)
  assert.equal(surface.handlers["pointercancel.scrub"], null)
})
