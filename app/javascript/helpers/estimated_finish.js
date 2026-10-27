import { formatDuration, formatPace } from "helpers/formatters"

export function nextIndex(index, count) {
  return (index + 1) % count
}

export function finishRow({ label, km, seconds }) {
  return { label, time: formatDuration(seconds), pace: formatPace(seconds / km) }
}
