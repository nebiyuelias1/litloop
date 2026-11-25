import { Controller } from "@hotwired/stimulus"

// Stops a form being submitted twice; shows a busy label meanwhile. Unlocks
// when the page comes back from the back/forward cache.
export default class extends Controller {
  static targets = ["button"]
  static values = { busyLabel: String }

  connect() {
    this.restore = (event) => { if (event.persisted) this.unlock() }
    window.addEventListener("pageshow", this.restore)
  }

  disconnect() {
    window.removeEventListener("pageshow", this.restore)
  }

  lock(event) {
    if (this.locked) {
      event.preventDefault()
      return
    }
    this.locked = true
    const button = this.buttonTarget
    this.label = button.textContent
    // Next frame, so the button's value is still submitted.
    requestAnimationFrame(() => {
      button.disabled = true
      button.setAttribute("aria-busy", "true")
      if (this.hasBusyLabelValue) button.textContent = this.busyLabelValue
    })
  }

  unlock() {
    this.locked = false
    const button = this.buttonTarget
    button.disabled = false
    button.removeAttribute("aria-busy")
    if (this.label) button.textContent = this.label
  }
}
