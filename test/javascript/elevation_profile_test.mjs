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

const { profilePoints, profileDomain, peakPoint } = await import("helpers/elevation_profile")

test("points pair distance in km with altitude and skip missing altitude", () => {
  assert.deepEqual(profilePoints([0, 500, 1000, 1500], [100, null, 110, 105]), [{ km: 0, alt: 100 }, { km: 1, alt: 110 }, { km: 1.5, alt: 105 }])
})

test("a flat run keeps a 150 m range above its low point", () => {
  const points = profilePoints([0, 1000, 2000], [100, 103, 101])

  assert.deepEqual(profileDomain(points), [95, 250])
})

test("a hilly run uses its real maximum when it passes the floor", () => {
  const points = profilePoints([0, 1000, 2000], [100, 400, 250])

  assert.deepEqual(profileDomain(points), [95, 400])
})

test("the peak is the highest point and the first one on a tie", () => {
  const points = profilePoints([0, 1000, 2000, 3000], [100, 120, 120, 90])

  assert.deepEqual(peakPoint(points), { km: 1, alt: 120 })
})
