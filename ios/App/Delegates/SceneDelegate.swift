//
//  SceneDelegate.swift
//  LitLoop
//
//  Created by Nebiyu Talefe on 2026/6/27.
//

import HotwireNative
import TelegramLogin
import UIKit

let baseURL = URL(string: "https://litloop.club/")!

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    private let tabBarController = HotwireTabBarController()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        configureTabBarAppearance()
        window?.rootViewController = tabBarController
        tabBarController.load(HotwireTab.all)

        if let userActivity = connectionOptions.userActivities.first,
           userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            handleIncomingURL(url)
        } else if let urlContext = connectionOptions.urlContexts.first {
            if !handleTelegramLoginURL(urlContext.url) {
                handleIncomingURL(urlContext.url)
            }
        } else if let path = initialPathFromLaunchArguments() {
            let url = (path.hasPrefix("http://") || path.hasPrefix("https://"))
                ? (URL(string: path) ?? baseURL)
                : (URL(string: "litloop://" + path) ?? baseURL)
            handleIncomingURL(url)
        }
    }

    // Allows automated screenshots to open a route without the system's
    // "Open in LitLoop?" confirmation, e.g.:
    //   xcrun simctl launch <udid> et.netale.litloop -initialPath /book_clubs/1
    private func initialPathFromLaunchArguments() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-initialPath"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        handleIncomingURL(url)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        if handleTelegramLoginURL(url) { return }
        handleIncomingURL(url)
    }

    // Telegram Login (https://core.telegram.org/bots/telegram-login#native-sdks):
    // the web button triggers litloop://telegram-login, which the WebView hands
    // to the system and back into this app. Without a code it starts the flow
    // (the SDK opens the Telegram app); with one it completes it.
    private func handleTelegramLoginURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "litloop",
              url.host?.lowercased() == "telegram-login" else {
            return false
        }

        if url.query?.contains("code=") == true {
            TelegramLogin.handle(url)
            return true
        }

        TelegramLogin.login { [weak self] result in
            switch result {
            case .success(let loginData):
                self?.routeTelegramSignIn(idToken: loginData.idToken)
            case .failure(let error):
                NSLog("TelegramLogin failed: \(error.localizedDescription)")
            }
        }
        return true
    }

    // Complete the sign-in inside the app's own WebView, so the session cookie
    // lands in the app.
    private func routeTelegramSignIn(idToken: String) {
        var components = URLComponents(url: baseURL.appending(path: "telegram_login/oidc"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id_token", value: idToken)]

        DispatchQueue.main.async {
            guard let url = components.url else { return }
            self.tabBarController.activeNavigator.route(url)
        }
    }

    private func handleIncomingURL(_ url: URL) {
        let webURL: URL
        if url.scheme?.lowercased() == "litloop" {
            let incomingComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            let host = incomingComponents.percentEncodedHost ?? ""
            let path = incomingComponents.percentEncodedPath
            let fullPath = (host + path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)!
            components.percentEncodedPath = "/" + fullPath
            components.percentEncodedQuery = incomingComponents.percentEncodedQuery
            components.percentEncodedFragment = incomingComponents.percentEncodedFragment
            webURL = components.url ?? baseURL
        } else if url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
            webURL = url
        } else {
            return
        }

        let path = webURL.path.lowercased()
        let targetIndex: Int
        if path.hasPrefix("/library") || path.hasPrefix("/books") {
            targetIndex = 1
        } else if path.hasPrefix("/book_clubs") {
            targetIndex = 2
        } else if path.hasPrefix("/profile") || path.hasPrefix("/users") {
            targetIndex = 3
        } else {
            targetIndex = 0
        }

        tabBarController.selectedIndex = targetIndex
        tabBarController.activeNavigator.route(webURL)
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        tabBarController.tabBar.standardAppearance = appearance
        tabBarController.tabBar.scrollEdgeAppearance = appearance
    }
}
