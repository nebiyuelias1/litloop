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
    clearTimeout(this.saveTimer)
  }

  // Debounced so arrowing 1 → 5 through the radios sends one request, not four.
  rate(event) {
    const score = parseInt(event.target.value, 10)
    clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.save(score), this.delayValue)
  }

  async save(score) {
    if (score === this.currentValue) return

    try {
      const response = await fetch(`/books/${this.bookIdValue}/ratings`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ rating: { score } })
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      this.currentValue = score
      window.toast?.(this.savedTextValue, { type: "success" })
    } catch (error) {
      console.error("Error saving rating:", error)
      this.restore()
      window.toast?.(this.failedTextValue, { type: "error" })
    }
  }

  // Put the radios back on the last saved score (or none).
  restore() {
    this.inputTargets.forEach((input) => {
      input.checked = parseInt(input.value, 10) === this.currentValue
    })
  }
}
