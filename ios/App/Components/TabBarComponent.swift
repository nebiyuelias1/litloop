//
//  TabBarComponent.swift
//  LitLoop
//

import HotwireNative
import UIKit

// Tab bar visibility per page (bridge--tab-bar):
//   "show"              normal pages
//   "hide"              the onboarding tour
//   "hide-when-pushed"  account pages, unless first in their tab (a guest's
//                       Library/Profile tab starts on sign in)
// Hidden at launch; restored when a hiding page disappears.
final class TabBarComponent: BridgeComponent {
    override class var name: String { "tab-bar" }

    /// Whether a visible page has sent a message yet.
    private static var pageDecided = false

    /// Hides the bar at launch; shows it after `fallback` seconds if no page says (e.g. offline).
    static func hideWhileLoading(_ tabBarController: UITabBarController, fallback: TimeInterval = 10) {
        tabBarController.setTabBarHidden(true, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + fallback) { [weak tabBarController] in
            guard !pageDecided else { return }
            tabBarController?.setTabBarHidden(false, animated: true)
        }
    }

    override func onReceive(message: Message) {
        guard isInSelectedTab else { return }
        Self.pageDecided = true

        if message.event == "show" {
            setTabBarHidden(false)
        } else if shouldHide {
            setTabBarHidden(true)
        }
    }

    // Back to this page, e.g. from sign up.
    override func onViewWillAppear() {
        if shouldHide { setTabBarHidden(true) }
    }

    override func onViewWillDisappear() {
        if shouldHide { setTabBarHidden(false) }
    }

    private var shouldHide: Bool {
        if receivedMessage(for: "hide") != nil { return true }
        if receivedMessage(for: "hide-when-pushed") != nil { return isPushed }
        return false
    }

    private var isPushed: Bool {
        guard let viewController, let stack = viewController.navigationController?.viewControllers else { return false }
        return stack.first !== viewController
    }

    private var isInSelectedTab: Bool {
        guard let navigationController = viewController?.navigationController else { return false }
        return navigationController.tabBarController?.selectedViewController === navigationController
    }

    private func setTabBarHidden(_ hidden: Bool) {
        viewController?.tabBarController?.setTabBarHidden(hidden, animated: true)
    }

    private var viewController: UIViewController? {
        delegate?.destination as? UIViewController
    }
}
