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

const { zoneBands, zoneStops } = await import("helpers/hr_zones")

const BANDS = [
  { zone: 1, from: 100, to: 120 },
  { zone: 2, from: 120, to: 140 },
  { zone: 3, from: 140, to: 160 },
  { zone: 4, from: 160, to: 180 },
  { zone: 5, from: 180, to: null }
]

test("bands inside the domain are kept and the open top zone runs to the domain top", () => {
  assert.deepEqual(zoneBands(BANDS, 90, 200), BANDS.map(band => ({ ...band, to: band.to ?? 200 })))
})

test("bands are clipped to the domain and bands outside it are dropped", () => {
  assert.deepEqual(zoneBands(BANDS, 130, 170), [
    { zone: 2, from: 130, to: 140 },
    { zone: 3, from: 140, to: 160 },
    { zone: 4, from: 160, to: 170 }
  ])
})

test("a domain below every band has none", () => {
  assert.deepEqual(zoneBands(BANDS, 40, 90), [])
})

test("stops change colour at each boundary, with the lowest zone extended below its floor", () => {
  assert.deepEqual(zoneStops(BANDS, 80, 200), [
    { offset: 0, zone: 1 },
    { offset: 20 / 120, zone: 1 }, { offset: 40 / 120, zone: 1 },
    { offset: 40 / 120, zone: 2 }, { offset: 60 / 120, zone: 2 },
    { offset: 60 / 120, zone: 3 }, { offset: 80 / 120, zone: 3 },
    { offset: 80 / 120, zone: 4 }, { offset: 100 / 120, zone: 4 },
    { offset: 100 / 120, zone: 5 }, { offset: 1, zone: 5 }
  ])
})

test("stops of a clipped domain start at its bottom and a domain below every band has none", () => {
  assert.deepEqual(zoneStops(BANDS, 130, 150), [
    { offset: 0, zone: 2 }, { offset: 0.5, zone: 2 },
    { offset: 0.5, zone: 3 }, { offset: 1, zone: 3 }
  ])
  assert.deepEqual(zoneStops(BANDS, 40, 90), [])
})
