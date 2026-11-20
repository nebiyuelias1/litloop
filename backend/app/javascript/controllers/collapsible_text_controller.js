import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["content", "toggle"];
  static values = {
    clampClass: { type: String, default: "line-clamp-4" },
    showMoreText: { type: String, default: "Show more" },
    showLessText: { type: String, default: "Show less" },
  };

  connect() {
    this.checkOverflow();
    this.resizeObserver = new ResizeObserver(() => this.checkOverflow());
    this.resizeObserver.observe(this.contentTarget);
  }

  disconnect() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }
  }

  checkOverflow() {
    if (!this.contentTarget.classList.contains(this.clampClassValue)) {
      this.toggleTarget.classList.remove("hidden");
      this.toggleTarget.textContent = this.showLessTextValue;
      this.toggleTarget.setAttribute("aria-expanded", "true");
    } else if (this.contentTarget.scrollHeight > this.contentTarget.clientHeight) {
      this.toggleTarget.classList.remove("hidden");
      this.toggleTarget.textContent = this.showMoreTextValue;
      this.toggleTarget.setAttribute("aria-expanded", "false");
    } else {
      this.toggleTarget.classList.add("hidden");
    }
  }

  toggle() {
    if (this.contentTarget.classList.contains(this.clampClassValue)) {
      this.contentTarget.classList.remove(this.clampClassValue);
      this.toggleTarget.textContent = this.showLessTextValue;
      this.toggleTarget.setAttribute("aria-expanded", "true");
    } else {
      this.contentTarget.classList.add(this.clampClassValue);
      this.toggleTarget.textContent = this.showMoreTextValue;
      this.toggleTarget.setAttribute("aria-expanded", "false");
    }
  }
}
