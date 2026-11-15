import { Controller } from "@hotwired/stimulus"

// Telegram Login (OpenID Connect) — https://core.telegram.org/bots/telegram-login
// Opens Telegram's auth page in a popup and posts the resulting id_token to the
// server, which validates it (JWKS signature, issuer, audience, expiry, nonce)
// before signing the user in.
//
// The popup URL is built here rather than by the official telegram-login.js
// library, because the library omits the `origin` parameter that Telegram's
// /auth endpoint requires (it needs both `origin` and `redirect_uri`). The
// result delivery is the same postMessage contract the library uses.
export default class extends Controller {
  static values = {
    clientId: Number,
    nonce: String,
    scope: { type: String, default: "profile" },
  }

  static TELEGRAM_OAUTH_ORIGIN = "https://oauth.telegram.org"

  disconnect() {
    window.removeEventListener("message", this.messageHandler)
    clearInterval(this.closeChecker)
  }

  open() {
    const popup = window.open(
      this.authUrl(),
      "telegram_oidc_login",
      "width=550,height=650,left=" +
        Math.max(0, (screen.width - 550) / 2) +
        ",top=" +
        Math.max(0, (screen.height - 650) / 2) +
        ",status=0,location=0,menubar=0,toolbar=0",
    )
    if (!popup) return

    this.messageHandler = (event) => {
      if (event.origin !== this.constructor.TELEGRAM_OAUTH_ORIGIN || event.source !== popup) return
      let data
      try {
        data = JSON.parse(event.data)
      } catch {
        return
      }
      if (data?.event !== "auth_result") return

      window.removeEventListener("message", this.messageHandler)
      clearInterval(this.closeChecker)
      this.onAuth(data)
    }
    window.addEventListener("message", this.messageHandler)

    // Stop listening if the popup is closed without completing the flow
    this.closeChecker = setInterval(() => {
      if (popup.closed) {
        clearInterval(this.closeChecker)
        window.removeEventListener("message", this.messageHandler)
      }
    }, 300)
  }

  authUrl() {
    const params = new URLSearchParams({
      response_type: "post_message",
      client_id: this.clientIdValue,
      origin: window.location.origin,
      redirect_uri: window.location.origin + window.location.pathname,
      scope: `openid ${this.scopeValue}`,
      nonce: this.nonceValue,
    })
    return `${this.constructor.TELEGRAM_OAUTH_ORIGIN}/auth?${params}`
  }

  async onAuth(data) {
    // user cancelled or Telegram reported an error client-side: stay on the page
    if (data.error || !data.result) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const body = new URLSearchParams({
      id_token: data.result,
      authenticity_token: csrfToken,
    })

    try {
      const response = await fetch("/telegram_login/oidc", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: body.toString(),
      })
      const result = await response.json()

      if (result.status === "ok" && result.redirect_url) {
        window.location.href = result.redirect_url
      } else {
        this.notify(result.error || "Telegram sign-in failed.")
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
