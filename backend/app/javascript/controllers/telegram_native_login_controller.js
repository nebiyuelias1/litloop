import { Controller } from "@hotwired/stimulus"

// Native app Telegram login (NEB-100).
//
// Telegram's widget popup can't complete inside the app's WebView, so this
// navigates to Telegram's OAuth page in the external browser (Hotwire routes
// cross-origin urls to a Custom Tab / SFSafariViewController). While the user
// completes sign-in there, this polls the handoff endpoint; when the signed
// result has been relayed back, the sign-in completes inside the app's WebView
// (where the session cookie actually lives).
export default class extends Controller {
  static values = {
    authUrl: String,
    pollUrl: String,
  }

  static POLL_INTERVAL_MS = 2000

  open() {
    this.startPolling()
    // Top-level navigation; Hotwire routes it to the external browser.
    window.location.href = this.authUrlValue
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    if (this.pollTimer) return
    this.pollTimer = setInterval(() => this.poll(), this.constructor.POLL_INTERVAL_MS)
  }

  stopPolling() {
    clearInterval(this.pollTimer)
    this.pollTimer = null
  }

  async poll() {
    try {
      const response = await fetch(this.pollUrlValue, { headers: { accept: "application/json" } })
      const result = await response.json()
      if (result.status === "ok" && result.redirect_url) {
        this.stopPolling()
        window.location.href = result.redirect_url
      }
    } catch {
      // Keep polling; transient network errors while the app resumes are fine
    }
  }
}
