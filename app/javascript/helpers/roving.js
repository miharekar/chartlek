export function rovingTarget(key, current, last) {
  const target = { ArrowLeft: current - 1, ArrowRight: current + 1, Home: 0, End: last }[key]
  return target == null ? null : Math.max(0, Math.min(last, target))
}

export function noMouseFocus(event) {
  const active = document.activeElement
  if (active && event.currentTarget.closest("svg")?.contains(active)) active.blur()
  event.preventDefault()
}
