import { formatDistanceRange } from "helpers/formatters"

export function elevationBins(bins, perKm = false) {
  const grouped = []
  for (let index = 0; index < bins.length; index += perKm ? 10 : 1) {
    const part = bins.slice(index, index + (perKm ? 10 : 1))
    const known = part.filter(bin => bin.gain != null)
    grouped.push({
      distance: part.reduce((sum, bin) => sum + bin.distance, 0),
      gain: known.length ? known.reduce((sum, bin) => sum + bin.gain, 0) : null,
      loss: known.length ? known.reduce((sum, bin) => sum + bin.loss, 0) : null,
      missing: part.some(bin => bin.missing || bin.gain == null)
    })
  }
  let distance = 0
  return grouped.map(bin => {
    const from = distance / 1000
    distance += bin.distance
    const to = distance / 1000
    const rows = bin.gain == null ? [["Elevation", "missing"]] : [["Gained", `${bin.gain.toFixed(1)} m`], ["Lost", `${bin.loss.toFixed(1)} m`]]
    if (bin.missing && bin.gain != null) rows.push(["Note", "some elevation missing"])
    const title = formatDistanceRange(from, to)
    return { from, to, up: bin.gain, down: bin.loss, title, rows, label: [title, ...rows.map(([name, value]) => `${name} ${value}`)].join(". ") }
  })
}
