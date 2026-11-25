import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Hides the apps' title bar on the onboarding tour. Only loads in the apps.
export default class extends BridgeComponent {
  static component = "navigation-bar"

  connect() {
    super.connect()
    this.send("hide")
  }
}
