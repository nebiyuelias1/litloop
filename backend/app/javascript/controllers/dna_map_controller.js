import { Controller } from "@hotwired/stimulus"

// Zoom & pan for the Literature DNA world map. All interaction mutates the
// SVG viewBox — no libraries, no server round-trips. Constraints: never
// smaller than the full map (scale >= 1), never larger than MAX_SCALE, and
// never panned past the map edges.
export default class extends Controller {
  static targets = ["svg"]

  static values = {
    maxScale: { type: Number, default: 6 },
  }

  connect() {
    this.svg = this.svgTarget
    const [x, y, w, h] = this.svg.getAttribute("viewBox").split(/\s+/).map(Number)
    this.base = { x, y, w, h }
    this.view = { ...this.base }
    this.pointers = new Map()
    this.pinchDistance = null

    this._onWheel = this.wheel.bind(this)
    this._onPointerDown = this.pointerDown.bind(this)
    this._onPointerMove = this.pointerMove.bind(this)
    this._onPointerUp = this.pointerUp.bind(this)
    this._onDblClick = this.dblClick.bind(this)

    this.svg.addEventListener("wheel", this._onWheel, { passive: false })
    this.svg.addEventListener("pointerdown", this._onPointerDown)
    this.svg.addEventListener("pointermove", this._onPointerMove)
    this.svg.addEventListener("pointerup", this._onPointerUp)
    this.svg.addEventListener("pointercancel", this._onPointerUp)
    this.svg.addEventListener("dblclick", this._onDblClick)
    this.svg.style.touchAction = "none"
    this.svg.style.cursor = "grab"
  }

  disconnect() {
    this.svg.removeEventListener("wheel", this._onWheel)
    this.svg.removeEventListener("pointerdown", this._onPointerDown)
    this.svg.removeEventListener("pointermove", this._onPointerMove)
    this.svg.removeEventListener("pointerup", this._onPointerUp)
    this.svg.removeEventListener("pointercancel", this._onPointerUp)
    this.svg.removeEventListener("dblclick", this._onDblClick)
  }

  zoomIn(event) { this.zoomStep(1 / 1.5, event) }
  zoomOut(event) { this.zoomStep(1.5, event) }
  reset() {
    this.view = { ...this.base }
    this.apply()
  }

  dblClick(event) {
    event.preventDefault()
    this.zoomAtPoint(1 / 1.6, this.svgPoint(event))
  }

  zoomStep(factor, event) {
    const rect = this.svg.getBoundingClientRect()
    const point = this.svgPoint({ clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2 })
    this.zoomAtPoint(factor, point)
  }

  wheel(event) {
    event.preventDefault()
    // Natural wheel zoom toward the cursor; ctrlKey (trackpad pinch) zooms faster.
    const intensity = event.ctrlKey ? 0.02 : 0.0035
    const factor = Math.exp(event.deltaY * intensity * (event.deltaMode === 1 ? 16 : 1))
    this.zoomAtPoint(factor, this.svgPoint(event))
  }

  pointerDown(event) {
    this.svg.setPointerCapture(event.pointerId)
    this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY })
    if (this.pointers.size === 2) {
      const [a, b] = [...this.pointers.values()]
      this.pinchDistance = Math.hypot(a.x - b.x, a.y - b.y)
    } else if (this.pointers.size === 1) {
      this.dragging = true
      this.svg.style.cursor = "grabbing"
    }
  }

  pointerMove(event) {
    if (!this.pointers.has(event.pointerId)) return
    const previous = this.pointers.get(event.pointerId)
    const current = { x: event.clientX, y: event.clientY }
    this.pointers.set(event.pointerId, current)

    if (this.pointers.size === 2 && this.pinchDistance) {
      // Pinch: scale around the midpoint, pan with the midpoint.
      const [a, b] = [...this.pointers.values()]
      const distance = Math.hypot(a.x - b.x, a.y - b.y)
      const factor = this.pinchDistance / distance
      this.pinchDistance = distance
      const mid = { clientX: (a.x + b.x) / 2, clientY: (a.y + b.y) / 2 }
      this.zoomAtPoint(factor, this.svgPoint(mid))
    } else if (this.pointers.size === 1 && this.dragging) {
      const rect = this.svg.getBoundingClientRect()
      const dx = ((current.x - previous.x) * this.view.w) / rect.width
      const dy = ((current.y - previous.y) * this.view.h) / rect.height
      this.pan(dx, dy)
    }
  }

  pointerUp(event) {
    this.pointers.delete(event.pointerId)
    if (this.pointers.size < 2) this.pinchDistance = null
    if (this.pointers.size === 0) {
      this.dragging = false
      this.svg.style.cursor = "grab"
    }
  }

  // ---- geometry ------------------------------------------------------------

  zoomAtPoint(factor, point) {
    const scale = this.currentScale() * factor
    const clamped = Math.min(this.maxScaleValue, Math.max(1, scale))
    const effective = clamped / this.currentScale()

    this.view.w /= effective
    this.view.h /= effective
    // Keep the cursor's map position fixed while scaling.
    this.view.x = point.x - (point.x - this.view.x) * effective
    this.view.y = point.y - (point.y - this.view.y) * effective
    this.clampAndApply()
  }

  pan(dx, dy) {
    this.view.x -= dx
    this.view.y -= dy
    this.clampAndApply()
  }

  currentScale() {
    return this.base.w / this.view.w
  }

  // Client (pixel) coordinates -> SVG user coordinates.
  svgPoint({ clientX, clientY }) {
    const rect = this.svg.getBoundingClientRect()
    return {
      x: this.view.x + ((clientX - rect.left) * this.view.w) / rect.width,
      y: this.view.y + ((clientY - rect.top) * this.view.h) / rect.height,
    }
  }

  clampAndApply() {
    const scale = this.currentScale()
    // Horizontal: clamp when the visible width is smaller than the map,
    // otherwise center the map (no empty space at the sides).
    if (this.view.w >= this.base.w) {
      this.view.x = this.base.x - (this.view.w - this.base.w) / 2
    } else {
      this.view.x = Math.min(this.base.x + this.base.w - this.view.w, Math.max(this.base.x, this.view.x))
    }
    if (this.view.h >= this.base.h) {
      this.view.y = this.base.y - (this.view.h - this.base.h) / 2
    } else {
      this.view.y = Math.min(this.base.y + this.base.h - this.view.h, Math.max(this.base.y, this.view.y))
    }
    if (scale.toFixed(2) === "1") Object.assign(this.view, this.base)
    this.apply()
  }

  apply() {
    const { x, y, w, h } = this.view
    this.svg.setAttribute("viewBox", `${x} ${y} ${w} ${h}`)
    const zoomed = this.currentScale() > 1.02
    this.svg.style.cursor = this.dragging ? "grabbing" : zoomed ? "grab" : "default"
  }
}
