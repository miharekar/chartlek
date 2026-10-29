import { snapToDays } from "helpers/time"

export const PRESETS = [
  { key: "3", months: 3 },
  { key: "6", months: 6 },
  { key: "12", months: 12 },
  { key: "24", months: 24 },
  { key: "all", months: null }
]

function monthsBack(date, months) {
  const total = date.getUTCFullYear() * 12 + date.getUTCMonth() - months
  const year = Math.floor(total / 12)
  const month = total % 12
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate()
  return new Date(Date.UTC(year, month, Math.min(date.getUTCDate(), lastDay)))
}

export function presetWindow(months, [first, last]) {
  const end = new Date(Date.UTC(last.getUTCFullYear(), last.getUTCMonth(), last.getUTCDate() + 1))
  const start = months == null ? first : monthsBack(last, months)
  return snapToDays([start, end], [first, end])
}

export function activePreset(range, domain) {
  const [start, end] = range.map(value => +new Date(value))
  const matches = PRESETS.filter(({ months }) => {
    const [from, to] = presetWindow(months, domain).map(Number)
    return from === start && to === end
  })
  return matches.at(-1)?.key
}
