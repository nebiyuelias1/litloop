package et.netale.litloop.components

import android.view.View
import androidx.core.view.isVisible
import dev.hotwire.core.bridge.BridgeComponent
import dev.hotwire.core.bridge.BridgeDelegate
import dev.hotwire.core.bridge.Message
import dev.hotwire.navigation.destinations.HotwireDestination
import et.netale.litloop.R

// Tab bar visibility per page (bridge--tab-bar):
//   "show"              normal pages
//   "hide"              the onboarding tour
//   "hide-when-pushed"  account pages, unless first in their tab (a guest's
//                       Library/Profile tab starts on sign in)
// Hidden at launch; restored when a hiding page stops.
class TabBarComponent(
    name: String,
    private val bridgeDelegate: BridgeDelegate<HotwireDestination>
) : BridgeComponent<HotwireDestination>(name, bridgeDelegate) {

    override fun onReceive(message: Message) {
        // Every tab loads at launch; only the visible one counts.
        if (!isInSelectedTab()) return
        pageDecided = true

        if (message.event == "show") {
            setTabBarVisible(true)
        } else if (shouldHide()) {
            setTabBarVisible(false)
        }
    }

    // Back to this page, e.g. from sign up.
    override fun onStart() {
        if (shouldHide()) setTabBarVisible(false)
    }

    override fun onStop() {
        if (shouldHide()) setTabBarVisible(true)
    }

    private val fragment get() = bridgeDelegate.destination.fragment

    private fun shouldHide(): Boolean = when {
        receivedMessageFor("hide") != null -> true
        receivedMessageFor("hide-when-pushed") != null ->
            !bridgeDelegate.destination.navigator.isAtStartDestination()
        else -> false
    }

    private fun isInSelectedTab(): Boolean = fragment.view?.isShown == true

    private fun setTabBarVisible(visible: Boolean) {
        // The wrapper: Hotwire re-shows bottom_nav on every insets change.
        val activity = fragment.activity ?: return
        activity.findViewById<View>(R.id.bottom_bar)?.isVisible = visible
    }

    companion object {
        /** Whether a visible page has sent a message yet. */
        private var pageDecided = false

        /** Hides the bar at launch; shows it after [fallbackMillis] if no page says (e.g. offline). */
        fun hideWhileLoading(bottomBar: View, fallbackMillis: Long = 10_000) {
            pageDecided = false
            bottomBar.isVisible = false
            bottomBar.postDelayed({ if (!pageDecided) bottomBar.isVisible = true }, fallbackMillis)
        }
    }
}
