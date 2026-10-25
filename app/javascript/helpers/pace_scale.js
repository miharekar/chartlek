import { scaleLinear } from "d3-scale"
import { formatPace } from "helpers/formatters"

export function paceScale([fastest, slowest], range) {
  const speed = scaleLinear()
    .domain([3600 / fastest, 3600 / slowest])
    .range(range)
  const scale = pace => speed(3600 / pace)

  scale.invert = position => 3600 / speed.invert(position)
  scale.domain = () => [fastest, slowest]
  scale.range = () => range
  scale.ticks = (count = 6) =>
    speed
      .ticks(count)
      .filter(kmh => kmh > 0)
      .map(kmh => 3600 / kmh)
  scale.tickFormat = () => formatPace
  scale.copy = () => paceScale([fastest, slowest], range)
  return scale
}
