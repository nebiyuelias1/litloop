import { Controller } from "@hotwired/stimulus"

// Injects the official Telegram login widget so its button exactly fills this
// element's width, keeping it symmetrical with the other social buttons (NEB-100).
//
// The widget iframe can't be resized or restyled from outside, but the embed
// supports min_width/max_width attributes: the button width is pinned to that
// range and the iframe resizes to match. We measure this element and set
// min = max, so the button fills the slot.
//
// The official widget is kept (rather than a custom button) because it runs the
// auth flow inside its cross-origin iframe, which is what makes Telegram login
// work inside the Hotwire Native apps: popups and cross-origin redirects are
// routed to the external browser there, where the session cookie would never
// reach the app's WebView.
export default class extends Controller {
  static values = {
    bot: String,
    authUrl: String,
  }

  connect() {
    this.attempts = 0
    this.inject()
  }

  inject() {
    if (document.getElementById(this.iframeId)) return

    const width = Math.round(this.element.getBoundingClientRect().width)
    if (width < 100) {
      // Layout not ready yet — retry a few times before giving up
      if (++this.attempts <= 20) setTimeout(() => this.inject(), 100)
      return
    }

    const script = document.createElement("script")
    script.src = "https://telegram.org/js/telegram-widget.js?22"
    script.async = true
    script.setAttribute("data-telegram-login", this.botValue)
    script.setAttribute("data-size", "large")
    script.setAttribute("data-radius", "10")
    script.setAttribute("data-min-width", String(width))
    script.setAttribute("data-max-width", String(width))
    script.setAttribute("data-auth-url", this.authUrlValue)
    script.setAttribute("data-request-access", "write")
    this.element.appendChild(script)
  }

  get iframeId() {
    return `telegram-login-${this.botValue.replace(/[^a-z0-9_]/ig, "-")}`
  }
}
