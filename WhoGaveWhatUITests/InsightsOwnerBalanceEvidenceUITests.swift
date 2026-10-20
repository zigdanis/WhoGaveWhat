import XCTest

/// Temporary visual evidence for the Insights owner card and gift-count balances; remove after review.
/// The app has no seeding hook, so the data is created through the Add gift sheet, in Russian.
final class InsightsOwnerBalanceEvidenceUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 15
    private let owner = "Данис"
    private let anna = "Анна"
    private let boris = "Борис"
    private let vera = "Вера"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launchEnvironment["KS_START"] = "app"
        app.launchEnvironment["KS_RESET_SELF"] = "1"
        app.launchEnvironment["KS_CLOUD_ICONS"] = "stub"
        app.launchEnvironment["KS_CLOUD_ICON_CONSENT"] = "declined"
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: timeout))
    }

    override func tearDown() {
        if testRun?.failureCount ?? 0 > 0 {
            attach("insights-owner-failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "insights-owner-failure-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        super.tearDown()
    }

    func testInsightsOwnerCardAndCountBalances() throws {
        // Anna gave two gifts to the owner (+2); the owner gave Boris two (−2);
        // with Vera the counts are equal but the money is not (even).
        addGift("Книга", from: anna, to: owner, value: "1500", createGiver: true, createRecipient: true)
        addGift("Конфеты", from: anna, to: owner, value: "700")
        addGift("Шарф", from: owner, to: boris, value: "800", createRecipient: true)
        addGift("Кружка", from: owner, to: boris, value: "600")
        addGift("Открытка", from: vera, to: owner, value: "1000", createGiver: true)
        addGift("Часы", from: owner, to: vera, value: "2500")

        openInsights()
        let hint = app.buttons["year-summary.mark-self"]
        XCTAssertTrue(hint.waitForExistence(timeout: timeout))
        attach("insights-mark-self-hint")

        markOwnerAsMe()
        openInsights()

        let ownerHeader = element(identifier: "year-summary.owner")
        XCTAssertTrue(ownerHeader.waitForExistence(timeout: timeout))
        XCTAssertTrue(ownerHeader.label.contains(owner), ownerHeader.label)
        XCTAssertFalse(hint.exists)
        attach("insights-owner-card")

        let evenRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Поровну")).firstMatch
        for _ in 0..<4 where !evenRow.exists || !evenRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(evenRow.waitForExistence(timeout: timeout))
        XCTAssertTrue(evenRow.label.contains(vera), evenRow.label)
        attach("insights-count-balances")
    }

    private func addGift(
        _ name: String, from giver: String, to recipient: String, value: String,
        createGiver: Bool = false, createRecipient: Bool = false
    ) {
        app.tabBars.buttons["Главная"].tap()
        app.buttons["Добавить подарок"].tap()
        let field = app.textFields["add-gift.name"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        waitForKeyboardFocus(field)
        field.typeText(name)
        choosePerson(giver, endpoint: "from", create: createGiver)
        choosePerson(recipient, endpoint: "to", create: createRecipient)

        let amount = app.textFields["add-gift.value"]
        if !amount.exists { app.buttons["add-gift.details"].tap() }
        XCTAssertTrue(amount.waitForExistence(timeout: timeout))
        amount.tap()
        waitForKeyboardFocus(amount)
        amount.typeText(value)

        let save = app.buttons["add-gift.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        waitForDisappearance(save)
    }

    private func choosePerson(_ name: String, endpoint: String, create: Bool) {
        app.buttons["add-gift.\(endpoint)"].tap()
        let query = app.textFields["person-picker.query"]
        XCTAssertTrue(query.waitForExistence(timeout: timeout))
        if create {
            query.tap()
            waitForKeyboardFocus(query)
            query.typeText(name)
            app.buttons["person-picker.add"].tap()
        } else {
            let row = app.buttons.matching(
                NSPredicate(
                    format: "identifier BEGINSWITH 'person-picker.person.' AND (label == %@ OR label ENDSWITH %@)",
                    name, ", \(name)")
            ).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: timeout))
            row.tap()
        }
        waitForDisappearance(query)
        waitForValue(app.buttons["add-gift.\(endpoint)"], expected: name)
    }

    private func markOwnerAsMe() {
        selectTab("Люди")
        let row = app.staticTexts[owner]
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        let meSwitch = app.switches["person-detail.is-me"]
        XCTAssertTrue(meSwitch.waitForExistence(timeout: timeout))
        // The switch sits at the trailing edge; the label area of a row toggle is not tappable.
        meSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.5)).tap()
        let on = NSPredicate(format: "value == %@", "1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: on, object: meSwitch)], timeout: timeout), .completed)
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func openInsights() {
        selectTab("Аналитика")
        XCTAssertTrue(app.navigationBars["Аналитика"].waitForExistence(timeout: timeout))
    }

    /// While scrolled down, the tab bar collapses to the current tab; scroll back up to expand it.
    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        for _ in 0..<3 where !tab.waitForExistence(timeout: 2) {
            app.swipeDown()
        }
        tab.tap()
    }

    private func waitForDisappearance(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func waitForKeyboardFocus(_ element: XCUIElement) {
        let focusedElement = app.descendants(matching: .any)
            .matching(identifier: element.identifier)
            .matching(NSPredicate(format: "hasKeyboardFocus == true"))
            .firstMatch
        // A tap during a sheet transition can be dropped on CI; re-tap once before failing.
        var focused = false
        for attempt in 1...2 where !focused {
            if attempt == 2, element.exists { element.tap() }
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true"), object: focusedElement)
            focused = XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
        }
        XCTAssertTrue(focused, "Text field did not acquire keyboard focus: \(element)")
    }

    private func waitForValue(_ element: XCUIElement, expected: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
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
