const OFFSET = 14
const ANCHOR_GAP = 6
const MARGIN = 8
const TOUCH_GAP = 48

let element
let owner

const ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, character => ESCAPES[character])
}

export function tooltipHtml(title, rows, { heading } = {}) {
  const grid = rows
    .filter(Boolean)
    .map(([label, value]) => `<div class="text-zinc-500 dark:text-zinc-400">${escapeHtml(label)}</div><div class="text-right">${escapeHtml(value)}</div>`)
    .join("")
  const top = heading ? `<div class="font-medium">${escapeHtml(heading)}</div>` : ""

  return `${top}<div class="mb-1 text-zinc-500 dark:text-zinc-400">${escapeHtml(title)}</div><div class="grid grid-cols-[auto_auto] gap-x-4">${grid}</div>`
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
  owner = null
  moveTooltip(event)
}

export function pointerPosition(point, size, viewport, touch = false) {
  if (touch) {
    const left = Math.max(MARGIN, Math.min(point.x - size.width / 2, viewport.width - size.width - MARGIN))
    const above = point.y - TOUCH_GAP - size.height
    return { left, top: above < MARGIN ? point.y + TOUCH_GAP : above }
  }
  const left = point.x + OFFSET + size.width > viewport.width ? point.x - OFFSET - size.width : point.x + OFFSET
  const top = point.y + OFFSET + size.height > viewport.height ? point.y - OFFSET - size.height : point.y + OFFSET
  return { left: Math.max(0, left), top: Math.max(0, top) }
}

export function moveTooltip(event) {
  const tooltip = tooltipElement()
  const { width, height } = tooltip.getBoundingClientRect()
  const { left, top } = pointerPosition({ x: event.clientX, y: event.clientY }, { width, height }, { width: window.innerWidth, height: window.innerHeight }, event.pointerType === "touch")
  tooltip.style.transform = `translate(${left}px, ${top}px)`
}

export function anchoredPosition(anchor, size, viewport) {
  const centered = anchor.left + anchor.width / 2 - size.width / 2
  const left = Math.max(MARGIN, Math.min(centered, viewport.width - size.width - MARGIN))
  const below = anchor.bottom + ANCHOR_GAP
  const top = below + size.height + MARGIN > viewport.height ? anchor.top - ANCHOR_GAP - size.height : below
  return { left, top: Math.max(0, top) }
}

export function showTooltipFor(html, anchor) {
  const tooltip = tooltipElement()
  tooltip.innerHTML = html
  tooltip.classList.remove("hidden")
  owner = anchor
  const { width, height } = tooltip.getBoundingClientRect()
  const { left, top } = anchoredPosition(anchor.getBoundingClientRect(), { width, height }, { width: window.innerWidth, height: window.innerHeight })
  tooltip.style.transform = `translate(${left}px, ${top}px)`
}

export function isTooltipFor(anchor) {
  return owner === anchor && Boolean(element?.isConnected) && !element.classList.contains("hidden")
}

export function hideTooltip() {
  owner = null
  element?.classList.add("hidden")
}
