const OFFSET = 14

let element

const ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, character => ESCAPES[character])
}

function tooltipElement() {
  if (element?.isConnected) return element
  element = document.createElement("div")
  element.className = "pointer-events-none fixed top-0 left-0 z-50 hidden max-w-xs rounded-md border border-zinc-200 bg-white px-2.5 py-1.5 text-xs text-zinc-900 tabular-nums shadow-lg dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-100"
  document.body.append(element)
  return element
}

export function showTooltip(html, event) {
  const tooltip = tooltipElement()
  tooltip.innerHTML = html
  tooltip.classList.remove("hidden")
  moveTooltip(event)
}

export function moveTooltip(event) {
  const tooltip = tooltipElement()
  const { width, height } = tooltip.getBoundingClientRect()
  const left = event.clientX + OFFSET + width > window.innerWidth ? event.clientX - OFFSET - width : event.clientX + OFFSET
  const top = event.clientY + OFFSET + height > window.innerHeight ? event.clientY - OFFSET - height : event.clientY + OFFSET
  tooltip.style.transform = `translate(${Math.max(0, left)}px, ${Math.max(0, top)}px)`
}

export function hideTooltip() {
  element?.classList.add("hidden")
}
