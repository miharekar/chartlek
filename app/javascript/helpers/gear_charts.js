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

export function visibleSpan(gears) {
  const used = gears.flatMap(gear => gear.km.flatMap((km, index) => (km > 0 ? [index] : [])))
  return used.length ? [Math.min(...used), Math.max(...used)] : null
}

export function zoom(months, gears, lead = 0) {
  const span = visibleSpan(gears)
  if (!span) return { months, gears }

  const from = Math.max(0, span[0] - lead)
  const to = lead > 0 ? Math.min(months.length, Math.max(span[1] + 1, from + 2)) : span[1] + 1
  return { months: months.slice(from, to), gears: gears.map(gear => ({ ...gear, km: gear.km.slice(from, to) })) }
}
