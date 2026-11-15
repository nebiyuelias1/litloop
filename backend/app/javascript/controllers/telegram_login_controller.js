import { Controller } from "@hotwired/stimulus"

// Custom Telegram login button (NEB-100).
// The official widget iframe has a fixed width, so instead we use Telegram's
// custom-button API: this controller initializes Telegram.Login with the bot id
// and, on click, opens the OAuth popup and redirects to the callback URL with
// the signed user payload (validated server-side by TelegramLoginController).
export default class extends Controller {
  static values = {
    botId: Number,
    authUrl: String,
    requestAccess: { type: String, default: "write" },
  }

  connect() {
    this.ready = false
    this.pending = false
    this.waitForTelegram()
  }

  waitForTelegram() {
    if (window.Telegram?.Login) {
      window.Telegram.Login.init(
        { bot_id: this.botIdValue, request_access: this.requestAccessValue },
        null,
      )
      this.ready = true

      if (this.pending) this.open()
    } else {
      // telegram-widget.js is loaded with `async`, so poll until its API exists
      setTimeout(() => this.waitForTelegram(), 100)
    }
  }

  open() {
    if (!this.ready) {
      this.pending = true
      return
    }

    window.Telegram.Login.open((user) => {
      if (!user) return

      const params = Object.entries(user)
        .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
        .join("&")
      const separator = this.authUrlValue.includes("?") ? "&" : "?"
      window.location.href = `${this.authUrlValue}${separator}${params}`
    })
  }
}
