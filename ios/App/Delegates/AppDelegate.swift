//
//  AppDelegate.swift
//  LitLoop
//
//  Created by Nebiyu Talefe on 2026/6/27.
//

import HotwireNative
import TelegramLogin
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        Hotwire.loadPathConfiguration(from: [
            .server(baseURL.appending(path: "configurations/ios_v1.json"))
        ])

        // Telegram Login SDK (https://core.telegram.org/bots/telegram-login#native-sdks).
        // The client id is the bot's numeric id (the TELEGRAM_BOT_TOKEN prefix,
        // matching the Rails side), read from Info.plist `TelegramLoginClientID`.
        let clientId = Bundle.main.object(forInfoDictionaryKey: "TelegramLoginClientID") as? String ?? ""
        if !clientId.isEmpty {
            TelegramLogin.configure(
                clientId: clientId,
                redirectUri: "litloop://telegram-login",
                scopes: ["profile"]
            )
        }

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

