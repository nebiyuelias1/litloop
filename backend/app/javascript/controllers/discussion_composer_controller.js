import { Controller } from "@hotwired/stimulus";

// Compact "Ask a question" trigger that expands into the full question form.
// The form stays open and resets after posting (reset-form controller) so
// several questions can be added in a row.
export default class extends Controller {
  static targets = ["trigger", "form", "textarea"];

  open() {
    this.triggerTarget.classList.add("hidden");
    this.formTarget.classList.remove("hidden");
    this.textareaTarget?.focus();
  }

  close() {
    this.formTarget.classList.add("hidden");
    this.triggerTarget.classList.remove("hidden");
    this.triggerTarget.focus();
  }
}
