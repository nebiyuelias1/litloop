import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "bookSection", "pollSection", "swapSection", "selectionBtn" ]

  connect() {
    this.toggle()
  }

  toggle(event) {
    let selection;
    if (event) {
      const input = event.currentTarget.querySelector('input[type="radio"]')
      if (input) {
        input.checked = true
        selection = input.value
      } else {
        selection = event.target.value
      }
    } else {
      // New sessions have radio buttons; edits carry the fixed type in a hidden field
      const checkedInput = this.element.querySelector('input[name="selection_type"]:checked') ||
        this.element.querySelector('input[type="hidden"][name="selection_type"]')
      selection = checkedInput ? checkedInput.value : "book"
    }

    // Update Section Visibility
    if (this.hasBookSectionTarget) this.bookSectionTarget.classList.toggle("hidden", selection !== "book")
    if (this.hasPollSectionTarget) this.pollSectionTarget.classList.toggle("hidden", selection !== "poll")
    if (this.hasSwapSectionTarget) this.swapSectionTarget.classList.toggle("hidden", selection !== "swap")

    // Update Toggle Button Styling
    this.selectionBtnTargets.forEach(btn => {
      const input = btn.querySelector('input')
      const label = btn.querySelector('span')
      const isSelected = input.value === selection
      
      if (isSelected) {
        btn.classList.add("bg-primary")
        btn.classList.remove("bg-transparent")
        if (label) {
          label.classList.remove("text-content")
          label.classList.add("text-primary-contrast")
        }
      } else {
        btn.classList.remove("bg-primary")
        btn.classList.add("bg-transparent")
        if (label) {
          label.classList.remove("text-primary-contrast")
          label.classList.add("text-content")
        }
      }
    })
  }
}
