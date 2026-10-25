import { parseTime } from "helpers/time"

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

const pad = number => String(number).padStart(2, "0")

export function formatPace(secondsPerKm) {
  const total = Math.round(secondsPerKm)
  return `${Math.floor(total / 60)}:${pad(total % 60)}`
}

export function formatDuration(seconds) {
  const total = Math.round(seconds)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const rest = pad(total % 60)
  return hours > 0 ? `${hours}:${pad(minutes)}:${rest}` : `${minutes}:${rest}`
}

export function formatDistance(km) {
  return km.toFixed(1)
}

export function formatDate(value) {
  const date = parseTime(value)
  return `${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]} ${date.getUTCFullYear()}`
}
