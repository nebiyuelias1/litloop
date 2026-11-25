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

    /// Whether this page hid the bar and hasn't restored it.
    private var hidTabBar = false

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

        // A root account page shows the bar (it may be hidden from launch).
        setTabBarHidden(message.event != "show" && shouldHide)
    }

    // Back to this page, e.g. from sign up.
    override func onViewWillAppear() {
        if shouldHide { setTabBarHidden(true) }
    }

    // Not shouldHide: on Back the stack has already popped this page.
    override func onViewWillDisappear() {
        if hidTabBar { setTabBarHidden(false) }
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
        guard let tabBarController = viewController?.tabBarController else { return }
        tabBarController.setTabBarHidden(hidden, animated: true)
        hidTabBar = hidden
    }

    private var viewController: UIViewController? {
        delegate?.destination as? UIViewController
    }
}
