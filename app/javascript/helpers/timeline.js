import { axisBottom } from "d3-axis"
import { brushX } from "d3-brush"
import { extent, max, rollup } from "d3-array"
import { select } from "d3-selection"
import { scaleLinear, scaleUtc } from "d3-scale"
import { utcDay } from "d3-time"
import { observeSize } from "helpers/resize"
import { snapToDays } from "helpers/time"

const MARGIN = { top: 4, right: 12, bottom: 20, left: 12 }

export function createTimeline(element, { data, domain, selection, height = 72, onBrush = () => {}, onEnd = () => {} }) {
  const days = [
    ...rollup(
      data,
      rows => rows.reduce((sum, row) => sum + row.value, 0),
      row => +utcDay.floor(row.date)
    )
  ].map(([time, value]) => ({ date: new Date(time), value }))
  const [first, last] = domain || extent(days, day => day.date)
  const fullDomain = [utcDay.floor(first), utcDay.offset(utcDay.floor(last), 1)]
  const y = scaleLinear()
    .domain([0, max(days, day => day.value) || 1])
    .range([height - MARGIN.bottom, MARGIN.top])
  const x = scaleUtc().domain(fullDomain)
  const brush = brushX()
  const svg = select(element).append("svg").attr("class", "block w-full").attr("height", height)
  const bars = svg.append("g").attr("fill", "var(--chart-accent)")
  const axis = svg.append("g").attr("transform", `translate(0,${height - MARGIN.bottom})`)
  const brushGroup = svg.append("g")
  let current = selection && snapToDays(selection, fullDomain)
  let silent = false
  let drawn = false

  function draw(width) {
    if (width - MARGIN.left - MARGIN.right <= 0) return

    x.range([MARGIN.left, width - MARGIN.right])
    svg.attr("width", width)
    bars
      .selectAll("rect")
      .data(days)
      .join("rect")
      .attr("x", day => x(day.date))
      .attr("width", day => Math.max(1, x(utcDay.offset(day.date, 1)) - x(day.date) - 0.5))
      .attr("y", day => y(day.value))
      .attr("height", day => y(0) - y(day.value))
    axis.call(
      axisBottom(x)
        .ticks(Math.max(2, Math.floor(width / 90)))
        .tickSizeOuter(0)
    )
    axis.select(".domain").attr("stroke", "var(--chart-grid)")
    axis.selectAll(".tick line").attr("stroke", "var(--chart-grid)")
    axis.selectAll("text").attr("fill", "var(--chart-axis)")
    brush.extent([
      [MARGIN.left, MARGIN.top],
      [width - MARGIN.right, height - MARGIN.bottom]
    ])
    brushGroup.call(brush)
    brushGroup.select(".selection").attr("fill", "var(--chart-accent-highlight)").attr("fill-opacity", 0.25).attr("stroke", "var(--chart-accent-highlight)")
    drawn = true
    if (current) move(current)
  }

  function move(range) {
    const wasSilent = silent
    silent = true
    brushGroup.call(brush.move, range.map(x))
    silent = wasSilent
  }

  brush.on("brush end", event => {
    if (silent) return
    if (event.type === "end" && !event.selection) return current && move(current)
    const range = snapToDays(event.selection.map(x.invert), fullDomain)
    current = range
    if (event.type === "end") {
      if (event.sourceEvent) move(range)
      onEnd(range)
    } else {
      onBrush(range)
    }
  })

  function setSelection(range) {
    current = snapToDays(range, fullDomain)
    if (drawn) move(current)
  }

  const disconnect = observeSize(element, ({ width }) => draw(width))

  return {
    setSelection,
    selection: () => current,
    destroy() {
      disconnect()
      svg.remove()
    }
  }
}
