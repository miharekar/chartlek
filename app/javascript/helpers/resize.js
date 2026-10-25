export function observeSize(element, callback) {
  const observer = new ResizeObserver(([entry]) => callback({ width: entry.contentRect.width, height: entry.contentRect.height }))
  observer.observe(element)
  return () => observer.disconnect()
}
