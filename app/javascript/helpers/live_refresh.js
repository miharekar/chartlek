export const TICK_MS = 30000

export function linkStep({ seen, dropped }, connected) {
  if (connected) return { seen: true, dropped: false, refresh: dropped }
  return { seen, dropped: seen, refresh: false }
}

export function shouldRefresh(reconnected, editing) {
  return reconnected && !editing
}

export function timeAgoWords(seconds) {
  const minutes = Math.round(Math.max(seconds, 0) / 60)
  if (minutes === 0) return "less than a minute"
  if (minutes === 1) return "1 minute"
  if (minutes < 45) return `${minutes} minutes`
  if (minutes < 90) return "about 1 hour"
  if (minutes < 1440) return `about ${Math.round(minutes / 60)} hours`
  if (minutes < 2520) return "1 day"
  if (minutes < 43200) return `${Math.round(minutes / 1440)} days`
  return null
}
