import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["star", "message"]
  static values = {
    bookId: Number,
    current: Number
  }

  connect() {
    this.updateStars(this.currentValue)
  }

  hover(event) {
    const value = parseInt(event.currentTarget.dataset.ratingValue)
    this.updateStars(value)
  }

  unhover() {
    this.updateStars(this.currentValue)
  }

  async rate(event) {
    const score = parseInt(event.currentTarget.dataset.ratingValue)
    this.currentValue = score
    this.updateStars(score)

    try {
      const response = await fetch(`/books/${this.bookIdValue}/ratings`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          rating: { score: score }
        })
      })

      if (response.ok) {
        const data = await response.json()
        toast('Rating saved.', { type: 'success' })
      } else {
        console.error('Failed to save rating')
      }
    } catch (error) {
      console.error('Error saving rating:', error)
    }
  }

  updateStars(value) {
    this.starTargets.forEach((star, index) => {
      const svg = star.querySelector('svg')
      if (index < value) {
        svg.classList.remove('text-content-muted')
        svg.classList.add('text-accent')
      } else {
        svg.classList.remove('text-accent')
        svg.classList.add('text-content-muted')
      }
    })
  }
}
