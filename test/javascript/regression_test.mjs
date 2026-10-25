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

const { linearRegression, weeklyChange } = await import("helpers/regression")

const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-9, `${actual} != ${expected}`)

test("linearRegression fits an exact line", () => {
  const fit = linearRegression([0, 1, 2, 3].map(x => ({ x, y: 2 * x + 5 })))

  close(fit.slope, 2)
  close(fit.intercept, 5)
  close(fit.sd, 0)
  close(fit.at(10), 25)
})

test("linearRegression computes the residual standard deviation", () => {
  const fit = linearRegression([
    { x: 0, y: 1 },
    { x: 1, y: 3 },
    { x: 2, y: 2 },
    { x: 3, y: 4 }
  ])

  close(fit.slope, 0.8)
  close(fit.intercept, 1.3)
  close(fit.sd, Math.sqrt(1.8 / 4))
})

test("linearRegression stays accurate with large x values", () => {
  const day = 20000
  const fit = linearRegression([0, 10, 20].map(offset => ({ x: day + offset, y: 500 + offset * 0.1 })))

  close(fit.slope, 0.1)
  close(fit.at(day), 500)
})

test("linearRegression needs two distinct points", () => {
  assert.equal(linearRegression([]), null)
  assert.equal(linearRegression([{ x: 1, y: 1 }]), null)
  assert.equal(linearRegression([{ x: 1, y: 1 }, { x: 1, y: 2 }]), null)
})

test("weeklyChange is the daily slope times seven", () => {
  close(weeklyChange(0.1), 0.7)
  close(weeklyChange(-0.5), -3.5)
})
