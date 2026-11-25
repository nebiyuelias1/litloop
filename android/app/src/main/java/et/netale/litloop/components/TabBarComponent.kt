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

    /** Whether this page hid the bar and hasn't restored it. */
    private var hidTabBar = false

    override fun onReceive(message: Message) {
        // Every tab loads at launch; only the visible one counts.
        if (!isInSelectedTab()) return
        pageDecided = true

        // A root account page shows the bar (it may be hidden from launch).
        setTabBarVisible(message.event == "show" || !shouldHide())
    }

    // Back to this page, e.g. from sign up.
    override fun onStart() {
        if (isInSelectedTab() && shouldHide()) setTabBarVisible(false)
    }

    // Not shouldHide(): on Back the stack has already popped this page.
    override fun onStop() {
        if (hidTabBar) setTabBarVisible(true)
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
        val bar = activity.findViewById<View>(R.id.bottom_bar) ?: return
        bar.isVisible = visible
        hidTabBar = !visible
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
