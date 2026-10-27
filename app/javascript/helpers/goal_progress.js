export const DAY = 86400000

export function dayIndexAt(time, start, days) {
  return Math.max(0, Math.min(days - 1, Math.round((time - start) / DAY)))
}

export function pathAt(goalKm, days, index) {
  return (goalKm * (index + 1)) / days
}

export function hoverAt({ goal_km: goalKm, days, cumulative, open_today: openToday, ended }, index) {
  const last = cumulative.length - 1
  const done = cumulative[last] ?? 0
  const past = index <= last
  const path = pathAt(goalKm, days, openToday && index === last ? index - 1 : index)
  const required = index >= last && !ended ? Math.max(goalKm - done, 0) / (days - index) : null

  return { past, done: past ? cumulative[index] : null, path, delta: past ? cumulative[index] - path : null, remaining: Math.max(goalKm - done, 0), required }
}

export function catchUpOpacity(ratio) {
  if (ratio == null) return 1
  return Math.max(0.35, Math.min(1, 0.35 + (0.65 * (ratio - 1)) / 2))
}

export function catchUpLine({ goal_km: goalKm, days, cumulative, catch_up: catchUp }) {
  if (!catchUp) return null
  return [[cumulative.length - 1, cumulative.at(-1)], [days - 1, goalKm]]
}

export function yMax({ goal_km: goalKm, cumulative }) {
  return Math.max(goalKm, cumulative.at(-1) ?? 0)
}
