import { formatDuration } from "helpers/formatters"

export function formatChange(perWeek) {
  const text = Math.abs(perWeek).toFixed(2)
  if (Number(text) === 0) return `${text}/week`
  return `${perWeek > 0 ? "+" : "-"}${text}/week`
}

export function formatFinishDelta(seconds) {
  return { verb: seconds < 0 ? "Added" : "Cut", time: formatDuration(Math.abs(seconds)) }
}
