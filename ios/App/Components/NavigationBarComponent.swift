//
//  NavigationBarComponent.swift
//  LitLoop
//

import HotwireNative
import UIKit

// Hides the navigation bar on the onboarding tour (bridge--navigation-bar),
// unless the tour was pushed: then it keeps Back and swipe-back. The bar is
// shared by the stack, so it's restored when the page disappears.
final class NavigationBarComponent: BridgeComponent {
    override class var name: String { "navigation-bar" }

    override func onReceive(message: Message) {
        if shouldHide { setNavigationBarHidden(true) }
    }

    override func onViewWillAppear() {
        if shouldHide { setNavigationBarHidden(true) }
    }

    override func onViewWillDisappear() {
        setNavigationBarHidden(false)
    }

    private var shouldHide: Bool {
        guard receivedMessage(for: "hide") != nil,
              let viewController,
              let stack = viewController.navigationController?.viewControllers else { return false }
        return stack.first === viewController
    }

    private func setNavigationBarHidden(_ hidden: Bool) {
        viewController?.navigationController?.setNavigationBarHidden(hidden, animated: true)
    }

    private var viewController: UIViewController? {
        delegate?.destination as? UIViewController
    }
}
