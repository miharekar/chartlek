import { bisector } from "d3-array"
import { dailyAverage } from "helpers/wellness"

const DAY_MS = 86400000
const BY_TIME = bisector(point => point[0])

export const OVERLAYS = {
  rhr: { label: "Resting HR", unit: "bpm", tooltip: "Resting HR (7-day avg)" },
  hrv: { label: "HRV", unit: "ms", tooltip: "HRV (last night)" },
  sleep: { label: "Sleep", unit: "h", tooltip: "Sleep (night before)", digits: 1 }
}

export function overlaySeries(overlays, key) {
  const values = overlays?.[key]
  if (!values) return []
  const smoothed = key === "rhr" ? dailyAverage(values) : key === "sleep" ? values.map(seconds => (seconds == null ? null : seconds / 3600)) : values
  return smoothed.map((value, index) => [overlays.start + index * DAY_MS, value])
}

export function overlayWithin(series, start, end) {
  return series.slice(BY_TIME.left(series, start), BY_TIME.left(series, end))
}

export function overlayAt(series, ms) {
  if (!series.length || ms < series[0][0]) return
  return series[Math.floor((ms - series[0][0]) / DAY_MS)]?.[1] ?? undefined
}
