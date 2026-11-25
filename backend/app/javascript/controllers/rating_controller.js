import { Controller } from "@hotwired/stimulus"

// Star rating backed by native radio inputs (arrow keys, checked state and
// screen-reader semantics come from the browser). Visual state is pure CSS
// on :checked, so this controller only persists the choice.
export default class extends Controller {
  static targets = ["input"]
  static values = {
    bookId: Number,
    current: Number,
    savedText: { type: String, default: "Your rating was saved." },
    failedText: { type: String, default: "Your rating couldn't be saved. Please try again." },
    delay: { type: Number, default: 400 }
  }

  disconnect() {
    // Don't drop a choice still waiting on the debounce.
    if (this.pending !== undefined) {
      clearTimeout(this.saveTimer)
      this.queue(this.pending)
    }
  }

  // Debounced so arrowing 1 → 5 through the radios sends one request, not four.
  rate(event) {
    this.pending = parseInt(event.target.value, 10)
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.queue(this.pending), this.delayValue)
  }

  // One request at a time; only the latest choice is sent next.
  queue(score) {
    this.pending = undefined
    this.wanted = score
    if (!this.saving) this.flush()
  }

  async flush() {
    this.saving = true
    while (this.wanted !== undefined) {
      const score = this.wanted
      this.wanted = undefined
      if (score !== this.currentValue) await this.save(score)
    }
    this.saving = false
  }

  async save(score) {
    try {
      const response = await fetch(`/books/${this.bookIdValue}/ratings`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ rating: { score } }),
        keepalive: true
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      this.currentValue = score
      if (this.isLatest()) window.toast?.(this.savedTextValue, { type: "success" })
    } catch (error) {
      console.error("Error saving rating:", error)
      // A newer choice is on screen and still to be sent; leave it.
      if (this.isLatest()) this.restore()
      window.toast?.(this.failedTextValue, { type: "error" })
    }
  }

  isLatest() {
    return this.wanted === undefined && this.pending === undefined
  }

  // Put the radios back on the last saved score (or none).
  restore() {
    this.inputTargets.forEach((input) => {
      input.checked = parseInt(input.value, 10) === this.currentValue
    })
  }
}
