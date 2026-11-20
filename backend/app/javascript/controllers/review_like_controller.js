import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count", "text", "icon"]
  static values = {
    reviewId: Number,
    bookId: Number,
    liked: Boolean,
    oneText: { type: String, default: "like" },
    otherText: { type: String, default: "likes" }
  }

  connect() {
    this.updateAppearance()
  }

  async toggle() {
    // Optimistic UI update
    this.likedValue = !this.likedValue
    const countEl = this.countTarget
    const textEl = this.hasTextTarget ? this.textTarget : null
    let currentCount = parseInt(countEl.textContent) || 0
    currentCount += this.likedValue ? 1 : -1
    countEl.textContent = currentCount
    if (textEl) textEl.textContent = this.label(currentCount)
    this.updateAppearance()

    try {
      const response = await fetch(`/books/${this.bookIdValue}/reviews/${this.reviewIdValue}/like`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.likedValue = data.liked
        countEl.textContent = data.likes_count
        if (textEl) textEl.textContent = this.label(data.likes_count)
        this.updateAppearance()
      } else {
        // Revert on failure
        this.likedValue = !this.likedValue
        currentCount += this.likedValue ? 1 : -1
        countEl.textContent = currentCount
        if (textEl) textEl.textContent = this.label(currentCount)
        this.updateAppearance()
      }
    } catch (error) {
      // Revert on error
      this.likedValue = !this.likedValue
      currentCount = parseInt(countEl.textContent) || 0
      currentCount += this.likedValue ? 1 : -1
      countEl.textContent = currentCount
      if (textEl) textEl.textContent = this.label(currentCount)
      this.updateAppearance()
      console.error('Error toggling like:', error)
    }
  }

  label(count) {
    return count === 1 ? this.oneTextValue : this.otherTextValue
  }

  updateAppearance() {
    const icon = this.iconTarget
    icon.classList.toggle('text-accent', this.likedValue)
    icon.classList.toggle('text-content-muted', !this.likedValue)
    icon.closest('button')?.setAttribute('aria-pressed', String(this.likedValue))
  }
}
