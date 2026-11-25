package et.netale.litloop.components

import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isVisible
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination

// Hides the toolbar on the onboarding tour (bridge--navigation-bar), unless the
// tour was pushed: then it keeps the back arrow.
class NavigationBarComponent(
    name: String,
    private val bridgeDelegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, bridgeDelegate) {

    override fun onReceive(message: Message) {
        if (message.event != "hide") return
        val destination = bridgeDelegate.destination
        if (!destination.navigator.isAtStartDestination()) return

        val toolbar = destination.toolbarForNavigation() ?: return
        toolbar.isVisible = false

        // Keep the app bar at status-bar height; empty, it would collapse.
        val appBar = toolbar.parent as? View ?: return
        val statusBar = ViewCompat.getRootWindowInsets(appBar)
            ?.getInsets(WindowInsetsCompat.Type.statusBars())?.top ?: 0
        appBar.minimumHeight = statusBar
    }
}
