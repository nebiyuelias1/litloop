import { Controller } from "@hotwired/stimulus"

// Switches the onboarding book picks between catalogue languages.
export default class extends Controller {
  static targets = ["tab", "panel"]

  select(event) {
    const lang = event.currentTarget.dataset.lang
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-pressed", String(tab.dataset.lang === lang)))
    this.panelTargets.forEach((panel) => panel.classList.toggle("hidden", panel.dataset.lang !== lang))
  }
}
