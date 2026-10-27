const WALK_BELOW_KMH = 5.5
const PACE_STEP_KMH = 0.5
const PACE_ZOOM = 36
const PACE_HALF_WINDOW_M = 50
const GRADE_HALF_WINDOW_M = 100
const GRADE_LIMIT = 10
const GRADE_STEP = 2
const GRADE_BUCKETS = (GRADE_LIMIT * 2) / GRADE_STEP
const CADENCE_FLOORS = [150, 160, 170, 180, 190]
const MINUS = "−"

export const BIN_M = 100

export function paceZone(kmh) {
  if (kmh < WALK_BELOW_KMH) return 0
  return Math.min(1 + Math.floor((kmh - WALK_BELOW_KMH) / PACE_STEP_KMH), PACE_ZOOM)
}

export function bucketOf(metric, value, floors) {
  if (value == null) return null
  if (metric === "pace") return paceZone(value)
  if (metric === "hr") return Math.max(0, floors.filter(floor => value >= floor).length - 1)
  if (metric === "grade") return Math.max(0, Math.min(GRADE_BUCKETS - 1, Math.floor((value + GRADE_LIMIT) / GRADE_STEP)))
  return CADENCE_FLOORS.filter(floor => value >= floor).length
}

export function bucketLabels(metric, { floors = [], paceLabels = [] } = {}) {
  if (metric === "pace") return paceLabels.map((label, index) => ({ label, title: index === 0 ? "Walk" : `${label} /km and faster` }))
  if (metric === "hr") return floors.map((floor, index) => ({ label: `Z${index + 1}`, title: `Zone ${index + 1}, ${floor}${index < floors.length - 1 ? `–${floors[index + 1] - 1}` : "+"} bpm` }))
  if (metric === "grade") {
    const sign = value => (value < 0 ? `${MINUS}${-value}` : String(value))
    return Array.from({ length: GRADE_BUCKETS }, (_, index) => {
      const low = -GRADE_LIMIT + index * GRADE_STEP
      const title = index === 0 ? `Below ${sign(low + GRADE_STEP)}%` : index === GRADE_BUCKETS - 1 ? `Above ${sign(low)}%` : `${sign(low)} to ${sign(low + GRADE_STEP)}%`
      return { label: sign(low), title }
    })
  }
  return [{ label: `<${CADENCE_FLOORS[0]}`, title: `Under ${CADENCE_FLOORS[0]} spm` }, ...CADENCE_FLOORS.map((floor, index) => {
    const next = CADENCE_FLOORS[index + 1]
    return { label: next ? String(floor) : `${floor}+`, title: next ? `${floor}–${next - 1} spm` : `${floor} spm and up` }
  })]
}

function slope(series, distances, half) {
  const last = distances.length - 1
  let low = 0
  let high = 0
  return distances.map((distance, index) => {
    while (low < index && distances[low + 1] <= distance - half) low++
    high = Math.max(high, index)
    while (high < last && distances[high] < distance + half) high++
    const span = distances[high] - distances[low]
    if (series[low] == null || series[high] == null || span <= 0) return null
    return (series[high] - series[low]) / span
  })
}

function average(series, index) {
  const values = [series[index - 1], series[index]].filter(value => value != null)
  return values.length ? values.reduce((sum, value) => sum + value) / values.length : null
}

export function buildSegments(data) {
  const { t, d, lat = [], lng = [], alt, hr = [], cad = [] } = data
  const paces = slope(t, d, PACE_HALF_WINDOW_M)
  const grades = alt ? slope(alt, d, GRADE_HALF_WINDOW_M) : []
  const segments = []
  const located = index => lat[index] != null && lng[index] != null
  let previous = located(0) ? 0 : null

  for (let index = 1; index < d.length; index++) {
    const distance = d[index] - d[index - 1]
    const time = t[index] - t[index - 1]
    if (distance < 0 || (distance === 0 && time <= 0)) continue

    const pace = distance > 0 ? average(paces, index) ?? time / distance : null
    const grade = average(grades, index)
    const line = distance > 0 && located(index) && previous != null ? [[lng[previous], lat[previous]], [lng[index], lat[index]]] : null
    if (distance > 0 && located(index)) previous = index
    segments.push({
      from: d[index - 1],
      to: d[index],
      distance,
      time,
      kmh: distance === 0 ? 0 : pace > 0 ? 3.6 / pace : null,
      grade: grade == null ? null : grade * 100,
      hr: average(hr, index),
      cad: average(cad, index),
      line
    })
  }
  return segments
}

export function segmentValue(segment, metric) {
  if (metric === "pace") return segment.kmh
  if (metric === "hr") return segment.hr
  if (metric === "grade") return segment.grade
  return segment.cad
}

export function nextSelection(selection, bucket) {
  if (selection?.bucket !== bucket) return { bucket, step: 1 }
  return selection.step === 3 ? null : { bucket, step: selection.step + 1 }
}

export function bucketSelected(selection, bucket) {
  if (selection.step === 1) return bucket === selection.bucket
  return selection.step === 2 ? bucket >= selection.bucket : bucket <= selection.bucket
}

export function selectionWeights(segments, buckets, selection) {
  if (!selection) return null
  if (selection.bucket != null) return buckets.map(bucket => (bucket != null && bucketSelected(selection, bucket) ? 1 : 0))
  return segments.map(segment => {
    if (segment.distance === 0) return segment.from >= selection.from && segment.from <= selection.to ? 1 : 0
    return Math.max(0, Math.min(selection.to, segment.to) - Math.max(selection.from, segment.from)) / segment.distance
  })
}

export function distribution(segments, buckets, count) {
  const totals = Array.from({ length: count }, () => ({ distance: 0, time: 0 }))
  segments.forEach((segment, index) => {
    if (buckets[index] == null) return
    totals[buckets[index]].distance += segment.distance
    totals[buckets[index]].time += segment.time
  })
  return totals
}

export function selectionStats(segments, weights) {
  let distance = 0
  let time = 0
  const weighted = { hr: [0, 0], cad: [0, 0] }

  segments.forEach((segment, index) => {
    const weight = weights ? weights[index] : 1
    if (weight <= 0) return

    distance += segment.distance * weight
    time += segment.time * weight
    for (const key of ["hr", "cad"]) {
      if (segment[key] == null) continue
      weighted[key][0] += segment[key] * segment.time * weight
      weighted[key][1] += segment.time * weight
    }
  })

  const mean = ([sum, weight]) => (weight > 0 ? sum / weight : null)
  return { distance, time, pace: distance > 0 ? time / (distance / 1000) : null, hr: mean(weighted.hr), cad: mean(weighted.cad) }
}

function emptyBin(bin, size) {
  return { from: bin * size, distance: 0, time: 0, selected: 0, sums: { hr: [0, 0], cad: [0, 0], grade: [0, 0] } }
}

export function bins(segments, weights, size = BIN_M) {
  const result = []

  segments.forEach((segment, index) => {
    const weight = weights ? weights[index] : 1
    if (segment.distance === 0) {
      const bin = Math.max(0, Math.ceil(segment.from / size) - 1)
      const entry = (result[bin] ??= emptyBin(bin, size))
      entry.time += segment.time
      return
    }

    for (let bin = Math.floor(segment.from / size); bin * size < segment.to; bin++) {
      const share = (Math.min(segment.to, (bin + 1) * size) - Math.max(segment.from, bin * size)) / segment.distance
      if (share <= 0) continue

      const entry = (result[bin] ??= emptyBin(bin, size))
      entry.distance += segment.distance * share
      entry.time += segment.time * share
      entry.selected += segment.distance * share * weight
      for (const key of ["hr", "cad", "grade"]) {
        if (segment[key] == null) continue
        entry.sums[key][0] += segment[key] * segment.distance * share
        entry.sums[key][1] += segment.distance * share
      }
    }
  })

  const mean = ([sum, weight]) => (weight > 0 ? sum / weight : null)
  return result.filter(Boolean).map(({ from, distance, time, selected, sums }) => ({
    from,
    to: from + distance,
    distance,
    time,
    pace: time > 0 && distance > 0 ? time / (distance / 1000) : null,
    hr: mean(sums.hr),
    cad: mean(sums.cad),
    grade: mean(sums.grade),
    selected: weights ? selected / distance >= 0.5 : true
  }))
}
