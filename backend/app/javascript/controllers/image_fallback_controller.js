import { Controller } from "@hotwired/stimulus"

// Hides an <img> whose source failed to load (404, bad URL, network drop),
// revealing the placeholder markup that sits beneath it in the DOM.
//
// Each view renders its fallback placeholder behind the image at all times,
// so this controller only ever has to hide the broken image:
//
//   <figure class="relative bg-background">
//     <div class="absolute inset-0 flex items-center justify-center"><!-- icon --></div>
//     <img src="..." data-controller="image-fallback"
//          data-action="error->image-fallback#fail" class="absolute inset-0">
//   </figure>
export default class extends Controller {
  connect() {
    // The error can fire before Stimulus connects (Turbo cache restore,
    // slow JS), so also detect an already-broken image here.
    if (this.element.src && this.element.complete && this.element.naturalWidth === 0) {
      this.fail()
    } else if (this.element.complete) {
      this.check()
    }
  }

  // Google Books answers a missing cover with a 200 OK "image not available"
  // PNG (always 300x391) instead of an error, so the error action never fires.
  // Wire it with `load->image-fallback#check` to treat that stand-in as broken.
  check() {
    const { naturalWidth, naturalHeight, src } = this.element
    if (src.includes("books.google.") && naturalWidth === 300 && naturalHeight === 391) {
      this.fail()
    }
  }

  fail(event) {
    event?.preventDefault()
    this.element.classList.add("hidden")
  }
}
