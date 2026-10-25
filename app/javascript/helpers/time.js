import { utcDay } from "d3-time"

export function parseTime(value) {
  return new Date(value)
}

export function snapToDays([start, end], bounds) {
  let first = utcDay.round(start)
  let last = utcDay.round(end)
  if (bounds) {
    first = new Date(Math.max(first, bounds[0]))
    last = new Date(Math.min(last, bounds[1]))
  }
  if (last <= first) {
    if (bounds && first >= bounds[1]) {
      first = utcDay.offset(bounds[1], -1)
      last = bounds[1]
    } else {
      last = utcDay.offset(first, 1)
    }
  }
  return [first, last]
}
