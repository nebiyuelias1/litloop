import { Controller } from "@hotwired/stimulus"

// Telegram Login (OpenID Connect) — https://core.telegram.org/bots/telegram-login
// Opens Telegram's auth popup via the official library and posts the resulting
// id_token to the server, which validates it (JWKS signature, issuer, audience,
// nonce) before signing the user in.
export default class extends Controller {
  static values = {
    clientId: Number,
    nonce: String,
    scope: { type: String, default: "profile" },
  }

  static POLL_INTERVAL_MS = 200
  static POLL_MAX_ATTEMPTS = 30

  connect() {
    // Disabled until the SDK is available, so clicks are never silently dropped.
    this.element.disabled = true
    this.attempts = 0
    this.waitForLibrary()
  }

  disconnect() {
    clearTimeout(this.retryTimeout)
  }

  waitForLibrary() {
    if (window.Telegram?.Login) {
      this.initLibrary()
      this.ready = true
      this.element.disabled = false
    } else if (++this.attempts >= this.constructor.POLL_MAX_ATTEMPTS) {
      // The script failed to load or is blocked — stop retrying and say so.
      this.notify("Telegram sign-in could not load. Please refresh and try again.")
    } else {
      // telegram-login.js is loaded with `async`, so retry until it is available
      this.retryTimeout = setTimeout(() => this.waitForLibrary(), this.constructor.POLL_INTERVAL_MS)
    }
  }

  open() {
    if (!this.ready) return
    // The SDK script can run again after this controller connected (e.g. a Turbo
    // visit re-executes the script tag) and replace window.Telegram.Login, so
    // (re-)apply our options and callback to the current object.
    this.initLibrary()
    window.Telegram.Login.open()
  }

  initLibrary() {
    window.Telegram.Login.init(
      {
        client_id: this.clientIdValue,
        scope: this.scopeValue.split(" "),
        nonce: this.nonceValue,
      },
      (result) => this.onAuth(result),
    )
  }

  async onAuth(result) {
    // popup_closed / user-cancelled / client-side errors: stay on the page
    if (!result || result.error || !result.id_token) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const body = new URLSearchParams({
      id_token: result.id_token,
      authenticity_token: csrfToken,
    })

    try {
      const response = await fetch("/telegram_login/oidc", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: body.toString(),
      })
      const data = await response.json()

      if (data.status === "ok" && data.redirect_url) {
        window.location.href = data.redirect_url
      } else {
        this.notify(data.error || "Telegram sign-in failed.")
      }
    } catch {
      this.notify("Network error, please try again.")
    }
  }

  notify(text, type = "error") {
    if (window.toast) {
      window.toast(text, { type })
    } else {
      alert(text)
    }
  }
}
