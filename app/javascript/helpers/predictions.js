export function predictTime(table, value) {
  const last = table.length - 1
  if (value <= table[0][0]) return table[0][1]
  if (value >= table[last][0]) return table[last][1]

  let low = 0
  let high = last
  while (high - low > 1) {
    const middle = (low + high) >> 1
    if (table[middle][0] <= value) low = middle
    else high = middle
  }

  const [x0, y0] = table[low]
  const [x1, y1] = table[high]
  return y0 + ((y1 - y0) * (value - x0)) / (x1 - x0)
}
