package et.netale.litloop

import android.app.Application
import dev.hotwire.core.bridge.BridgeComponentFactory
import dev.hotwire.core.config.Hotwire
import dev.hotwire.navigation.config.registerBridgeComponents
import et.netale.litloop.components.NavigationBarComponent
import et.netale.litloop.components.TabBarComponent

class LitLoopApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Before any web view exists, so the user agent lists them.
        Hotwire.registerBridgeComponents(
            BridgeComponentFactory("tab-bar", ::TabBarComponent),
            BridgeComponentFactory("navigation-bar", ::NavigationBarComponent)
        )
    }
}
