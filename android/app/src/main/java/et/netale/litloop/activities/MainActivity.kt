package et.netale.litloop.activities

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatDelegate
import com.google.android.material.bottomnavigation.BottomNavigationView
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.Navigator
import dev.hotwire.navigation.tabs.HotwireBottomNavigationController
import dev.hotwire.navigation.tabs.navigatorConfigurations
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets
import et.netale.litloop.BuildConfig
import et.netale.litloop.R
import et.netale.litloop.models.mainTabs
import android.util.Log
import com.linecorp.linesdk.LineApiResponseCode
import com.linecorp.linesdk.Scope
import com.linecorp.linesdk.auth.LineAuthenticationParams
import com.linecorp.linesdk.auth.LineLoginApi
import org.telegram.login.TelegramLogin

const val baseURL = "https://litloop.club/"

// Telegram Login SDK (https://core.telegram.org/bots/telegram-login#native-sdks).
// The button on the web login page triggers litloop://telegram-login, which the
// OS hands back to this activity; the SDK then opens the Telegram app for
// consent and delivers the id_token back through the same custom scheme.
const val telegramLoginRedirectUri = "litloop://telegram-login"

// LINE Login SDK (https://developers.line.biz/en/docs/line-login-sdks/android-sdk/).
// Same hand-off pattern via litloop://line-login; the SDK opens the LINE app
// (or an in-app login screen) and returns the access token through onActivityResult.
const val lineLoginRedirectTrigger = "litloop://line-login"
private const val LINE_LOGIN_REQUEST_CODE = 6094

class MainActivity : HotwireActivity() {
    private lateinit var bottomNavigationController: HotwireBottomNavigationController
    private var pendingDeepLink: DeepLink? = null

    private data class DeepLink(val url: String, val tabIndex: Int)

    override fun navigatorConfigurations() = mainTabs.navigatorConfigurations

    override fun onCreate(savedInstanceState: Bundle?) {
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_NO)
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.main).applyDefaultImeWindowInsets()
        initializeBottomTabs()
        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(
                remoteFileUrl = "$baseURL/configurations/android_v1.json"
            )
        )

        if (BuildConfig.TELEGRAM_LOGIN_CLIENT_ID.isNotBlank()) {
            TelegramLogin.init(
                clientId = BuildConfig.TELEGRAM_LOGIN_CLIENT_ID,
                redirectUri = telegramLoginRedirectUri,
                scopes = listOf("profile")
            )
        }
        if (savedInstanceState == null) {
            queueDeepLink(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val uri = intent.data ?: return queueDeepLink(intent)
        when {
            isSocialLoginTrigger(uri, "telegram-login") -> startTelegramLogin()
            isSocialLoginTrigger(uri, "line-login") -> startLineLogin()
            isTelegramLoginResponse(uri) -> handleTelegramLoginResponse(uri)
            else -> queueDeepLink(intent)
        }
    }

    override fun onNavigatorReady(navigator: Navigator) {
        super.onNavigatorReady(navigator)
        val pending = pendingDeepLink ?: return
        val targetTab = mainTabs.getOrNull(pending.tabIndex) ?: return
        if (navigator.configuration.name != targetTab.configuration.name) return

        selectTabIfNeeded(pending.tabIndex)
        routeDeepLinkWhenReady(navigator, pending)
    }

    private fun queueDeepLink(intent: Intent?) {
        val uri = intent?.data ?: return
        val targetUrl = resolveTargetUrl(uri) ?: return
        val pending = DeepLink(targetUrl, findTargetTabIndex(targetUrl))
        pendingDeepLink = pending

        routeDeepLinkIfReady(pending)
    }

    private fun routeDeepLinkIfReady(pending: DeepLink) {
        if (!::bottomNavigationController.isInitialized) return

        selectTabIfNeeded(pending.tabIndex)

        val targetTab = mainTabs.getOrNull(pending.tabIndex) ?: return
        val navigator = delegate.findNavigatorHost(targetTab.configuration.navigatorHostId)
            ?.takeIf { it.isReady() }
            ?.navigator
            ?: return

        routeDeepLinkWhenReady(navigator, pending)
    }

    private fun routeDeepLinkWhenReady(navigator: Navigator, pending: DeepLink) {
        val hostView = navigator.host.view ?: window.decorView

        hostView.post {
            if (pendingDeepLink != pending || isFinishing || isDestroyed) return@post

            selectTabIfNeeded(pending.tabIndex)
            pendingDeepLink = null
            navigator.route(pending.url)
        }
    }

    private fun selectTabIfNeeded(tabIndex: Int) {
        if (bottomNavigationController.view.selectedItemId != tabIndex) {
            bottomNavigationController.selectTab(tabIndex)
        }
    }

    private fun resolveTargetUrl(uri: Uri): String? {
        return when (uri.scheme?.lowercase()) {
            "litloop" -> {
                val path = (uri.host ?: "") + (uri.encodedPath ?: "")
                val query = uri.encodedQuery?.let { "?$it" } ?: ""
                val fragment = uri.encodedFragment?.let { "#$it" } ?: ""
                "${baseURL.trimEnd('/')}/${path.trimStart('/')}$query$fragment"
            }
            "http", "https" -> uri.toString()
            else -> null
        }
    }

    private fun isTelegramLoginTrigger(uri: Uri): Boolean {
        return isSocialLoginTrigger(uri, "telegram-login")
    }

    private fun isSocialLoginTrigger(uri: Uri, provider: String): Boolean {
        return uri.scheme?.lowercase() == "litloop" &&
            uri.host == provider &&
            uri.query.isNullOrBlank()
    }

    private fun isTelegramLoginResponse(uri: Uri): Boolean {
        return uri.scheme?.lowercase() == "litloop" &&
            uri.host == "telegram-login" &&
            !uri.query.isNullOrBlank()
    }

    private fun startTelegramLogin() {
        if (BuildConfig.TELEGRAM_LOGIN_CLIENT_ID.isBlank()) {
            Log.w("TelegramLogin", "TELEGRAM_LOGIN_CLIENT_ID is not configured")
            return
        }

        try {
            TelegramLogin.startLogin(this)
        } catch (e: Exception) {
            Log.e("TelegramLogin", "startLogin failed", e)
        }
    }

    private fun handleTelegramLoginResponse(uri: Uri) {
        TelegramLogin.handleLoginResponse(
            uri,
            onSuccess = { loginData ->
                // Complete the sign-in inside the app's own WebView, so the
                // session cookie lands in the app.
                routeAfterTelegramLogin(loginData.idToken)
            },
            onError = { error ->
                Log.e("TelegramLogin", "Login failed: ${error.message}")
            }
        )
    }

    private fun routeAfterTelegramLogin(idToken: String) {
        val url = Uri.parse("$baseURL/telegram_login/oidc").buildUpon()
            .appendQueryParameter("id_token", idToken)
            .build()
        val targetUrl = resolveTargetUrl(url) ?: return
        val pending = DeepLink(targetUrl, findTargetTabIndex(targetUrl))
        pendingDeepLink = pending
        routeDeepLinkIfReady(pending)
    }

    private fun startLineLogin() {
        if (BuildConfig.LINE_CHANNEL_ID.isBlank()) {
            Log.w("LineLogin", "LINE_CHANNEL_ID is not configured")
            return
        }

        try {
            val intent = LineLoginApi.getLoginIntent(
                this,
                BuildConfig.LINE_CHANNEL_ID,
                LineAuthenticationParams.Builder().scopes(listOf(Scope.PROFILE)).build()
            )
            startActivityForResult(intent, LINE_LOGIN_REQUEST_CODE)
        } catch (e: Exception) {
            Log.e("LineLogin", "startLogin failed", e)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != LINE_LOGIN_REQUEST_CODE) return

        val result = LineLoginApi.getLoginResultFromIntent(data)
        if (result.responseCode != LineApiResponseCode.SUCCESS || result.accessToken == null) {
            Log.e("LineLogin", "Login failed: ${result.errorData?.message ?: "unknown error"}")
            return
        }

        // Complete the sign-in inside the app's own WebView, so the session
        // cookie lands in the app. The server verifies the token with LINE's API.
        val url = Uri.parse("$baseURL/line_login/native").buildUpon()
            .appendQueryParameter("access_token", result.accessToken.accessToken)
            .build()
        val targetUrl = resolveTargetUrl(url) ?: return
        val pending = DeepLink(targetUrl, findTargetTabIndex(targetUrl))
        pendingDeepLink = pending
        routeDeepLinkIfReady(pending)
    }

    private fun findTargetTabIndex(url: String): Int {
        val path = Uri.parse(url).path ?: return 0
        return when {
            path.startsWith("/library") || path.startsWith("/books") -> 1
            path.startsWith("/book_clubs") -> 2
            path.startsWith("/profile") || path.startsWith("/users") -> 3
            else -> 0
        }
    }

    private fun initializeBottomTabs() {
        val bottomNavigationView =
            findViewById<BottomNavigationView>(R.id.bottom_nav)

        bottomNavigationController =
            HotwireBottomNavigationController(this, bottomNavigationView)
        bottomNavigationController.load(mainTabs, 0)
    }
}
