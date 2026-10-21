import XCTest

/// Finds tab buttons whichever way the system shows the tab bar. On iPhone Duo's outer
/// display, apps built with the iOS 27.1 SDK get a vertical bar under the status bar,
/// and XCUITest reports it as a toolbar instead of a tab bar.
extension XCUIApplication {
    /// The named tab's button, in the horizontal tab bar or else in the vertical bar.
    func tabButton(_ name: String) -> XCUIElement {
        tabBars.firstMatch.exists ? tabBars.buttons[name] : toolbars.buttons[name].firstMatch
    }

    /// Waits until the named tab shows in either bar, then returns its button.
    func waitForTabButton(_ name: String, timeout: TimeInterval) -> XCUIElement {
        let shown = NSPredicate { _, _ in
            self.tabBars.buttons[name].exists || self.toolbars.buttons[name].exists
        }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: shown, object: nil)], timeout: timeout)
        return tabButton(name)
    }

    /// Taps Back. The vertical bar on iPhone Duo's outer display also holds the Back button.
    func navigateBack() {
        let back = navigationBars.buttons.element(boundBy: 0)
        (back.exists ? back : buttons["BackButton"].firstMatch).tap()
    }

    /// Whether a tab bar with the named tab is on screen, horizontal or vertical.
    func showsTabBar(withTab name: String) -> Bool {
        tabBars.firstMatch.exists || toolbars.buttons[name].exists
    }
}
