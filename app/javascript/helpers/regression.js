export function linearRegression(points) {
  const count = points.length
  if (count < 2) return null

  let sumX = 0
  let sumY = 0
  for (const { x, y } of points) {
    sumX += x
    sumY += y
  }
  const meanX = sumX / count
  const meanY = sumY / count

  let sxx = 0
  let sxy = 0
  for (const { x, y } of points) {
    sxx += (x - meanX) ** 2
    sxy += (x - meanX) * (y - meanY)
  }
  if (sxx === 0) return null

  const slope = sxy / sxx
  const intercept = meanY - slope * meanX
  const squares = points.reduce((sum, { x, y }) => sum + (y - intercept - slope * x) ** 2, 0)

  return { slope, intercept, sd: Math.sqrt(squares / count), at: x => intercept + slope * x }
}

export function weeklyChange(slopePerDay) {
  return slopePerDay * 7
}
