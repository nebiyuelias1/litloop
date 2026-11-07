import { Controller } from "@hotwired/stimulus";

// Anchor section bar for the book-read page: smooth-scrolls to page sections
// and mirrors the section currently in view back onto the bar (scrollspy).
export default class extends Controller {
  static targets = ["link"];

  connect() {
    this.sections = this.linkTargets
      .map((link) => document.querySelector(link.getAttribute("href")))
      .filter(Boolean);
    this.suppressUntil = 0;

    this.observer = new IntersectionObserver(
      () => this.update(),
      { rootMargin: "-128px 0px -55% 0px" },
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
    // Tall sections overlap the observer band, so recomputation during the
    // smooth scroll would snap the highlight back; trust the click instead.
    this.suppressUntil = Date.now() + 800;
    const prefersReducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    section.scrollIntoView({
      behavior: prefersReducedMotion ? "auto" : "smooth",
      block: "start",
    });
    history.replaceState(null, "", link.getAttribute("href"));
    this.select(section);
  }

  update() {
    if (Date.now() < this.suppressUntil) return;
    // The section the reader is in is the last one whose top has crossed the
    // band floor; a previous tall section can still overlap the band without
    // being the one in view.
    const bandFloor = window.innerHeight * 0.45;
    const current = this.sections
      .filter((section) => section.getBoundingClientRect().top <= bandFloor)
      .pop();
    if (current) this.select(current);
  }

  select(section) {
    this.linkTargets.forEach((link) => {
      const isActive = link.getAttribute("href") === `#${section.id}`;
      link.setAttribute("aria-current", isActive ? "true" : "false");
    });
  }
}
