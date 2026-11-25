import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Tells the apps whether to show their tab bar: "show", "hide" or
// "hide-when-pushed" (see TabBarComponent). Only loads in the apps.
export default class extends BridgeComponent {
  static component = "tab-bar"
  static values = { event: { type: String, default: "hide" } }

  connect() {
    super.connect()
    this.send(this.eventValue)
  }
}
