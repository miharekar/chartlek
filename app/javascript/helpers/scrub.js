export function isTouch(event) {
  return event.pointerType === "touch"
}

export function scrub(selection, { enter, move, leave, mode = "surface" }) {
  const tap = mode === "tap"
  if (!tap) selection.each(function () { (this.ownerSVGElement ?? this).style.touchAction = "pan-y" })

  return selection
    .on("pointerdown.scrub", function (event, datum) {
      if (!isTouch(event)) return
      if (mode === "items") event.target.releasePointerCapture?.(event.pointerId)
      else move?.call(this, event, datum)
    })
    .on("pointerenter.scrub", enter)
    .on("pointermove.scrub", tap ? function (event, datum) { (isTouch(event) ? leave : move)?.call(this, event, datum) } : move)
    .on("pointercancel.scrub", tap ? leave : null)
    .on("pointerleave.scrub", tap ? function (event, datum) { if (!isTouch(event)) leave?.call(this, event, datum) } : leave)
}
