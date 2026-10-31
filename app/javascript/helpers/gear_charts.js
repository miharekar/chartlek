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

const TICK_STEPS = [1, 2, 3, 4, 6, 12, 24, 60, 120]
const LABEL_HALF_WIDTH = 14

export function monthTicks(months, width) {
  const first = months[0].getTime()
  const span = months.at(-1).getTime() - first
  const budget = Math.max(2, Math.floor(width / 80))
  const fits = date => span === 0 || ((date.getTime() - first) / span) * width <= width - LABEL_HALF_WIDTH
  const aligned = step => months.filter(date => date.getUTCMonth() % Math.min(step, 12) === 0 && (step <= 12 || date.getUTCFullYear() % (step / 12) === 0) && fits(date))
  const candidates = TICK_STEPS.map(aligned)

  return candidates.find(ticks => ticks.length > 0 && ticks.length <= budget) ?? [months[0]]
}

export const MAX_MONTH_TICKS = 18
const YEAR_LABEL_GAP = 48

export function barTicks(months, step) {
  const indexes = months.map((_, index) => index)
  if (months.length <= MAX_MONTH_TICKS) return indexes

  const keepFirst = (12 - months[0].getUTCMonth()) * step >= YEAR_LABEL_GAP
  return indexes.filter(index => months[index].getUTCMonth() === 0 || (index === 0 && keepFirst))
}
