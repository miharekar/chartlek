export function zoneBands(bands, low, high) {
  return bands
    .map(({ zone, from, to }) => ({ zone, from: Math.max(from, low), to: Math.min(to ?? high, high) }))
    .filter(band => band.from < band.to)
}
