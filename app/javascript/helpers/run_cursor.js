const listeners = new Set()
let latest = null
let frame = null

export function publish(distance) {
  latest = distance
  frame ??= requestAnimationFrame(flush)
}

export function clear() {
  publish(null)
}

export function subscribe(listener) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

function flush() {
  frame = null
  for (const listener of listeners) listener(latest)
}
