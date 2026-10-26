export function rovingTarget(key, current, last) {
  const target = { ArrowLeft: current - 1, ArrowRight: current + 1, Home: 0, End: last }[key]
  return target == null ? null : Math.max(0, Math.min(last, target))
}
