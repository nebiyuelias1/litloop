import { Controller } from "@hotwired/stimulus";

// Anchor section bar for the book-read page: smooth-scrolls to page sections
// and mirrors the section currently in view back onto the bar (scrollspy).
export default class extends Controller {
  static targets = ["link"];

  connect() {
    this.sections = this.linkTargets
      .map((link) => document.querySelector(link.getAttribute("href")))
      .filter(Boolean);
    this.visible = new Map();

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => this.visible.set(entry.target.id, entry.isIntersecting));
        // Several sections can cross the band at once; the topmost one in
        // document order is the one the reader is in.
        const current = this.sections.find((section) => this.visible.get(section.id));
        if (current) this.select(current);
      },
      { rootMargin: "-8rem 0px -55% 0px" },
    );
    this.sections.forEach((section) => this.observer.observe(section));
  }

  disconnect() {
    if (this.observer) this.observer.disconnect();
  }

  scroll(event) {
    const link = event.currentTarget;
    const section = document.querySelector(link.getAttribute("href"));
    if (!section) return;
    event.preventDefault();
    section.scrollIntoView({ behavior: "smooth", block: "start" });
    history.replaceState(null, "", link.getAttribute("href"));
    this.select(section);
  }

  select(section) {
    this.linkTargets.forEach((link) => {
      const isActive = link.getAttribute("href") === `#${section.id}`;
      link.setAttribute("aria-current", isActive ? "true" : "false");
    });
  }
}
