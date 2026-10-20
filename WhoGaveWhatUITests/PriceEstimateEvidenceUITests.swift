import XCTest

// TEMPORARY evidence for the gift price estimate PR: remove this file once the screenshots have
// been reviewed. The core journey stays in AdaptiveGiftJourneyUITests.
final class PriceEstimateEvidenceUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 12

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Russian UI and formatting, as the app is mostly used; amounts read like "10 000 ₽".
        // (With an English UI the same region formats rubles as "10 000 RUB".)
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        // Overrides the stored currency preference for this launch.
        app.launchArguments += ["-preferredCurrencyCode", "RUB"]
        app.launchEnvironment["KS_START"] = "app"
        app.launchEnvironment["KS_RESET_SELF"] = "1"
        app.launchEnvironment["KS_CLOUD_ICONS"] = "stub"
        app.launchEnvironment["KS_CLOUD_ICON_CONSENT"] = "allowed"
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: timeout))
    }

    override func tearDown() {
        if testRun?.failureCount ?? 0 > 0 {
            attach("failure-screen")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "failure-accessibility-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        super.tearDown()
    }

    func testEstimateShowsInCollapsedDetailsAndExpandedField() throws {
        XCTAssertTrue(app.buttons["Добавить подарок"].waitForExistence(timeout: timeout))
        app.buttons["Добавить подарок"].tap()
        let name = app.textFields["add-gift.name"]
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        name.typeText("гитара")

        // Collapsed: the estimate is visible next to the Details chevron.
        let summary = element(identifier: "add-gift.details.value")
        XCTAssertTrue(summary.waitForExistence(timeout: timeout))
        waitForNormalizedLabel(summary, expected: "≈ 10 000 ₽")
        XCTAssertFalse(app.textFields["add-gift.value"].exists)
        attach("price-estimate-details-collapsed")

        // Expanded: the field shows the number with its "≈" and "Suggested" hint.
        app.buttons["add-gift.details"].tap()
        let field = app.textFields["add-gift.value"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        XCTAssertTrue((field.value as? String)?.contains("10000") == true)
        attach("price-estimate-value-field")
    }

    func testSettingsOffersOnlyRublesAndDollars() throws {
        XCTAssertTrue(app.buttons["Настройки"].waitForExistence(timeout: timeout))
        app.buttons["Настройки"].tap()
        let currency = element(identifier: "settings.currency")
        XCTAssertTrue(currency.waitForExistence(timeout: timeout))
        currency.tap()
        XCTAssertTrue(element(identifier: "settings.currency.list").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(identifier: "settings.currency.RUB").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(identifier: "settings.currency.USD").exists)

        let identifiers = Set(
            app.descendants(matching: .any).allElementsBoundByIndex.map(\.identifier)
                .filter { $0.hasPrefix("settings.currency.") && $0 != "settings.currency.list" })
        XCTAssertEqual(identifiers, ["settings.currency.RUB", "settings.currency.USD"])
        attach("settings-currency-rub-usd")
    }

    private func waitForNormalizedLabel(_ element: XCUIElement, expected: String) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if normalized(element.label) == expected { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(normalized(element.label), expected)
    }

    /// Currency formatting uses no-break spaces between digit groups and before the symbol.
    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
