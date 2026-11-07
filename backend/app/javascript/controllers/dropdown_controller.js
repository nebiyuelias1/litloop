import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.boundHide = this.hide.bind(this)
    this.boundKeydown = this.handleKeydown.bind(this)

    // DaisyUI CSS dropdowns open on focus/hover with no Stimulus action, so the
    // trigger's aria-expanded must be kept in sync by observing focus movement.
    if (this.element.classList.contains("dropdown")) {
      this.boundFocusSync = () => this.setExpanded(this.element.contains(document.activeElement))
      this.element.addEventListener("focusin", this.boundFocusSync)
      this.element.addEventListener("focusout", this.boundFocusSync)
    }
  }

  toggle(event) {
    event.stopPropagation()
    const hidden = this.menuTarget.classList.toggle("hidden")
    this.setExpanded(!hidden)

    if (!hidden) {
      document.addEventListener("click", this.boundHide)
      document.addEventListener("keydown", this.boundKeydown)
    } else {
      document.removeEventListener("click", this.boundHide)
      document.removeEventListener("keydown", this.boundKeydown)
    }
  }

  hide(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      // Keyboard users don't lose their place: focus returns to the trigger.
      const trigger = this.element.querySelector("[aria-expanded]")
      if (trigger && trigger !== event.target) trigger.focus()
    }
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.setExpanded(false)
    document.removeEventListener("click", this.boundHide)
    document.removeEventListener("keydown", this.boundKeydown)
  }

  setExpanded(value) {
    const trigger = this.element.querySelector("[aria-expanded]")
    if (trigger) trigger.setAttribute("aria-expanded", String(value))
  }

  disconnect() {
    document.removeEventListener("click", this.boundHide)
    document.removeEventListener("keydown", this.boundKeydown)
    if (this.boundFocusSync) {
      this.element.removeEventListener("focusin", this.boundFocusSync)
      this.element.removeEventListener("focusout", this.boundFocusSync)
    }
  }
}
