import assert from "node:assert/strict"
import { registerHooks } from "node:module"
import { existsSync } from "node:fs"
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

globalThis.requestAnimationFrame = callback => setTimeout(callback, 0)
const nextFrame = () => new Promise(resolve => setTimeout(resolve, 5))

const { publish, clear, subscribe } = await import("helpers/run_cursor")
const { routeAt } = await import("helpers/route_point")

test("subscribers get the latest distance once per frame", async () => {
  const seen = []
  const stop = subscribe(distance => seen.push(distance))

  publish(100)
  publish(250)
  await nextFrame()

  assert.deepEqual(seen, [250])
  stop()
})

test("clear publishes null to every subscriber", async () => {
  const first = []
  const second = []
  const stops = [subscribe(distance => first.push(distance)), subscribe(distance => second.push(distance))]

  publish(10)
  await nextFrame()
  clear()
  await nextFrame()

  assert.deepEqual(first, [10, null])
  assert.deepEqual(second, [10, null])
  stops.forEach(stop => stop())
})

test("an unsubscribed listener hears nothing more", async () => {
  const seen = []
  const stop = subscribe(distance => seen.push(distance))

  publish(1)
  await nextFrame()
  stop()
  publish(2)
  await nextFrame()

  assert.deepEqual(seen, [1])
})

const route = [[10, 40], [12, 42], [16, 46]]
const distances = [0, 50, 150]

test("routeAt interpolates between the surrounding route points", () => {
  assert.deepEqual(routeAt(route, distances, 25), [11, 41])
  assert.deepEqual(routeAt(route, distances, 100), [14, 44])
  assert.deepEqual(routeAt(route, distances, 50), [12, 42])
})

test("routeAt clamps a hair past the ends but hides the marker beyond them", () => {
  assert.deepEqual(routeAt(route, distances, -20), [10, 40])
  assert.deepEqual(routeAt(route, distances, 170), [16, 46])
  assert.equal(routeAt(route, distances, 5000), null)
  assert.equal(routeAt(route, distances, -200), null)
})

test("routeAt does not invent a position across a GPS gap", () => {
  const gapped = [[10, 40], [11, 41], [20, 50], [21, 51]]
  const gappedDistances = [0, 50, 1050, 1100]

  assert.deepEqual(routeAt(gapped, gappedDistances, 25), [10.5, 40.5])
  assert.equal(routeAt(gapped, gappedDistances, 600), null)
  assert.deepEqual(routeAt(gapped, gappedDistances, 1075), [20.5, 50.5])
  assert.deepEqual(routeAt(gapped, [0, 50, 150, 200], 100), [15.5, 45.5])
})

test("routeAt copes with repeated distances, a single point and missing data", () => {
  assert.deepEqual(routeAt([[1, 2], [3, 4], [5, 6]], [0, 0, 10], 0), [3, 4])
  assert.deepEqual(routeAt([[1, 2]], [0], 5), [1, 2])
  assert.equal(routeAt([], [], 5), null)
  assert.equal(routeAt(route, [], 5), null)
  assert.equal(routeAt(route, [0, 100], 5), null)
})
