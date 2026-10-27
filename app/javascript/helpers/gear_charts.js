const GOLDEN_ANGLE = 137.5

export function seriesColor(index) {
  return `hsl(${Math.round((95 + index * GOLDEN_ANGLE) % 360)} 62% 50%)`
}

export function initialHidden(gears) {
  return new Set(gears.filter(gear => gear.retired).map(gear => gear.id))
}

export function toggled(hidden, id) {
  const next = new Set(hidden)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  return next
}

export function cumulative(values) {
  const first = values.findIndex(value => value > 0)
  if (first < 0) return values.map(() => null)

  let total = 0
  return values.map((value, index) => {
    total += value
    return index < first - 1 ? null : total
  })
}

export function stackRows(months, gears) {
  return months.map((month, index) => ({ month, ...Object.fromEntries(gears.map(gear => [gear.id, gear.km[index]])) }))
}

export function monthRows(gears, index) {
  return gears.map(gear => [gear, gear.km[index]]).filter(([, km]) => km > 0)
}
