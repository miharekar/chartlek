export function zoneBands(bands, low, high) {
  return bands
    .map(({ zone, from, to }) => ({ zone, from: Math.max(from, low), to: Math.min(to ?? high, high) }))
    .filter(band => band.from < band.to)
}

export function zoneStops(bands, low, high) {
  const clipped = zoneBands(bands, low, high)
  if (!clipped.length) return []

  const offset = value => (value - low) / (high - low)
  const stops = clipped.flatMap(({ zone, from, to }) => [{ offset: offset(from), zone }, { offset: offset(to), zone }])
  return stops[0].offset > 0 ? [{ offset: 0, zone: stops[0].zone }, ...stops] : stops
}
