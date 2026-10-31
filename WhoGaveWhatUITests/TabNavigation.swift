import XCTest

/// Finds tab buttons whichever way the system shows the tab bar. On iPhone Duo's outer
/// display, apps built with the iOS 27.1 SDK get a vertical bar under the status bar,
/// and XCUITest reports it as a toolbar instead of a tab bar. iPad's tab bar at the top
/// of the window reports its tabs as plain buttons outside any bar.
extension XCUIApplication {
    /// The named tab's button, in the horizontal tab bar, the vertical bar or iPad's top bar.
    func tabButton(_ name: String) -> XCUIElement {
        if tabBars.firstMatch.exists { return tabBars.buttons[name] }
        let inToolbar = toolbars.buttons[name].firstMatch
        return inToolbar.exists ? inToolbar : buttons[name].firstMatch
    }

    /// Waits until the named tab shows in any of those bars, then returns its button.
    func waitForTabButton(_ name: String, timeout: TimeInterval) -> XCUIElement {
        let shown = NSPredicate { _, _ in
            self.tabBars.buttons[name].exists || self.toolbars.buttons[name].exists
                || (!self.tabBars.firstMatch.exists && self.buttons[name].exists)
        }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: timeout)
        return tabButton(name)
    }

    /// Taps Back. The system Back button is `BackButton` in either bar; on iPhone Duo's outer
    /// display it sits in the vertical bar, where the navigation bar has no buttons.
    func navigateBack() {
        // Only the visible stack's Back button is hittable.
        let back = buttons.matching(identifier: "BackButton").allElementsBoundByIndex.first { $0.isHittable }
        (back ?? navigationBars.buttons.element(boundBy: 0)).tap()
    }
}
