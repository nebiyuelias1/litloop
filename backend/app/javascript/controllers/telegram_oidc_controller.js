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

  connect() {
    this.waitForLibrary()
  }

  disconnect() {
    clearTimeout(this.retryTimeout)
  }

  waitForLibrary() {
    if (window.Telegram?.Login) {
      window.Telegram.Login.init(
        {
          client_id: this.clientIdValue,
          scope: this.scopeValue.split(" "),
          nonce: this.nonceValue,
        },
        (result) => this.onAuth(result),
      )
      this.ready = true
    } else {
      // telegram-login.js is loaded with `async`, so retry until it is available
      this.retryTimeout = setTimeout(() => this.waitForLibrary(), 100)
    }
  }

  open() {
    if (this.ready) window.Telegram.Login.open()
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
        this.notify(data.error || "Telegram sign-in failed.", "error")
      }
    } catch {
      this.notify("Network error, please try again.", "error")
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
