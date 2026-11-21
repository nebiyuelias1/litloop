import { Controller } from "@hotwired/stimulus"

// Onboarding tour. Swiping is CSS scroll snap; this syncs the loop indicator,
// label, buttons and screen-reader status with the slide in view. Slides 2–5
// are the four stations on the loop; the last slide closes the loop.
const STATION_START = 0.125 // first station sits an eighth of the way along the path
const EASE_OUT = (t) => 1 - Math.pow(1 - t, 3)

export default class extends Controller {
  static targets = ["track", "slide", "loopPath", "loopTrail", "ribbon", "station", "marker", "stationLabel", "status", "back", "next", "skip", "tourBar", "finalBar"]
  static values = {
    names: Array,
    statusTemplate: String
  }

  connect() {
    this.current = -1
    this.progress = 0 // 0..1 around the loop, measured from the first station
    this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.path = this.loopPathTarget
    this.length = this.path.getTotalLength()
    this.stationTargets.forEach((dot, i) => this.place(dot, STATION_START + i / 4))

    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) this.show(this.slideTargets.indexOf(entry.target))
      })
    }, { root: this.trackTarget, threshold: 0.6 })
    this.slideTargets.forEach((slide) => this.observer.observe(slide))
    this.show(0)
  }

  disconnect() {
    this.observer?.disconnect()
    clearTimeout(this.closeLoopTimer)
    cancelAnimationFrame(this.frame)
  }

  next() {
    this.goTo(this.current + 1)
  }

  previous() {
    this.goTo(this.current - 1)
  }

  skip() {
    this.goTo(this.slideTargets.length - 1)
  }

  key(event) {
    if (event.key === "ArrowRight") { event.preventDefault(); this.next() }
    if (event.key === "ArrowLeft") { event.preventDefault(); this.previous() }
  }

  goTo(index) {
    const target = this.slideTargets[index]
    if (!target) return
    this.trackTarget.scrollTo({ left: target.offsetLeft, behavior: this.reducedMotion ? "auto" : "smooth" })
    this.show(index)
  }

  show(index) {
    if (index === this.current || index < 0) return
    this.current = index
    const last = this.slideTargets.length - 1
    const step = index // 0 = welcome, 1..4 = stations

    clearTimeout(this.closeLoopTimer)
    this.markerTarget.setAttribute("opacity", step === 0 ? "0" : "1")
    this.animateTo(step === 0 ? 0 : (step - 1) / 4)
    this.stationTargets.forEach((dot, i) => dot.toggleAttribute("data-reached", step > 0 && i < step))
    if (index === last) {
      this.closeLoopTimer = setTimeout(() => this.animateTo(1), this.reducedMotion ? 0 : 900)
    }

    const name = this.namesValue[step] || ""
    this.stationLabelTarget.textContent = step === 0 ? "" : name
    this.statusTarget.textContent = this.statusTemplateValue
      .replace("%{current}", index + 1)
      .replace("%{name}", name)

    // Off-screen slides stay out of the tab order.
    this.slideTargets.forEach((slide, i) => { slide.inert = i !== index })

    // Inline style: .btn-secondary overrides `hidden`.
    this.backTarget.disabled = index === 0
    this.backTarget.style.display = index === 0 ? "none" : ""
    this.skipTarget.classList.toggle("invisible", index === last)
    this.tourBarTarget.classList.toggle("hidden", index === last)
    this.finalBarTarget.classList.toggle("hidden", index !== last)
  }

  animateTo(target) {
    cancelAnimationFrame(this.frame)
    const from = this.progress
    if (this.reducedMotion || from === target) return this.draw(target)

    const started = performance.now()
    const duration = 650
    const tick = (now) => {
      const t = Math.min(1, (now - started) / duration)
      this.draw(from + (target - from) * EASE_OUT(t))
      if (t < 1) this.frame = requestAnimationFrame(tick)
    }
    this.frame = requestAnimationFrame(tick)
  }

  // Trail covers [start, start + p] of the closed path, wrapping past its end.
  draw(p) {
    this.progress = p
    const L = this.length
    const start = STATION_START * L
    const covered = p * L
    const wrapped = Math.max(0, start + covered - L) // part that runs past the path's end
    const main = covered - wrapped
    // [wrapped dash][gap to start][main dash][rest]
    this.loopTrailTarget.setAttribute("stroke-dasharray", `${wrapped} ${start - wrapped} ${main} ${L}`)
    this.place(this.markerTarget, STATION_START + p)
    this.ribbonTarget.setAttribute("opacity", p >= 0.999 ? "1" : "0")
  }

  place(element, fraction) {
    const point = this.path.getPointAtLength((((fraction % 1) + 1) % 1) * this.length)
    element.setAttribute("cx", point.x)
    element.setAttribute("cy", point.y)
  }
}
