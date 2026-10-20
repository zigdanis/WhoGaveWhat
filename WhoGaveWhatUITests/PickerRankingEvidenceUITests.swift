import XCTest

/// Temporary evidence for ranking the Add Gift pickers by recent use; removed after visual review.
final class PickerRankingEvidenceUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 12
    // The store survives between tests and starts empty apart from what earlier tests created, so every
    // person and occasion here is new and unique; nothing depends on pre-existing data.
    private let suffix = UUID().uuidString.prefix(6)
    private var giverName: String { "Rank Giver \(suffix)" }
    private var takerName: String { "Rank Taker \(suffix)" }
    private var firstOccasion: String { "Rank Party \(suffix)" }
    private var secondOccasion: String { "Rank Trip \(suffix)" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["KS_START"] = "app"
        app.launchEnvironment["KS_RESET_SELF"] = "1"
        app.launchEnvironment["KS_CLOUD_ICONS"] = "stub"
        app.launchEnvironment["KS_CLOUD_ICON_CONSENT"] = "declined"
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: timeout))
    }

    override func tearDown() {
        if testRun?.failureCount ?? 0 > 0 {
            attach("picker-ranking-failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "picker-ranking-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        super.tearDown()
    }

    /// Two saved gifts swap giver and recipient. Each picker then ranks by its own role: the person who
    /// just gave tops From, the one who just received tops To, and the newest occasion tops Occasion.
    func testRecentlyUsedPickerOptionsComeFirst() throws {
        // Gift 1: giver -> taker, first occasion. Everyone and everything is created through the pickers.
        openAddGift(named: "Rank gift one \(suffix)")
        choosePerson(giverName, endpoint: "from", create: true)
        choosePerson(takerName, endpoint: "to", create: true)
        chooseNewOccasion(firstOccasion)
        saveGift(named: "Rank gift one \(suffix)")

        // Gift 2: the roles swap, with a second occasion.
        openAddGift(named: "Rank gift two \(suffix)")
        choosePerson(takerName, endpoint: "from", create: false)
        choosePerson(giverName, endpoint: "to", create: false)
        chooseNewOccasion(secondOccasion)
        saveGift(named: "Rank gift two \(suffix)")

        // Gift 3 is only opened. The taker gave most recently and the giver received most recently, so
        // each tops exactly one picker even though both were used in both roles.
        openAddGift(named: "Rank gift three \(suffix)")
        verifyTopPeople(
            endpoint: "from", expected: [takerName, giverName], screenshot: "picker-ranking-from")
        verifyTopPeople(
            endpoint: "to", expected: [giverName, takerName], screenshot: "picker-ranking-to")
        verifyTopOccasions(expected: [secondOccasion, firstOccasion], screenshot: "picker-ranking-occasion")

        app.buttons["Cancel"].tap()
        waitForDisappearance(app.buttons["add-gift.save"])
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["Add a gift"].waitForExistence(timeout: timeout))
    }

    // MARK: Flow steps

    private func openAddGift(named name: String) {
        app.tabBars.buttons["Home"].tap()
        app.buttons["Add a gift"].tap()
        let field = app.textFields["add-gift.name"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        waitForKeyboardFocus(field)
        field.typeText(name)
    }

    /// Creates the person through the query field, or finds an existing one by filtering on their name,
    /// which keeps the ranked order and keeps the row inside the half-height sheet.
    private func choosePerson(_ name: String, endpoint: String, create: Bool) {
        app.buttons["add-gift.\(endpoint)"].tap()
        let query = app.textFields["person-picker.query"]
        XCTAssertTrue(query.waitForExistence(timeout: timeout))
        query.tap()
        waitForKeyboardFocus(query)
        query.typeText(name)
        if create {
            app.buttons["person-picker.add"].tap()
        } else {
            let rows = personRows(named: name)
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: timeout))
            XCTAssertEqual(rows.count, 1)
            rows.firstMatch.tap()
        }
        waitForDisappearance(query)
        waitForValue(app.buttons["add-gift.\(endpoint)"], expected: name)
    }

    /// Expands Details if needed, then adds a custom occasion, which selects it and closes the picker.
    private func chooseNewOccasion(_ name: String) {
        showDetails()
        app.buttons["add-gift.occasion"].tap()
        let occasion = app.textFields["add-gift.occasion.custom"]
        XCTAssertTrue(occasion.waitForExistence(timeout: timeout))
        occasion.tap()
        waitForKeyboardFocus(occasion)
        occasion.typeText(name)
        app.buttons["add-gift.occasion.add"].tap()
        waitForValue(app.buttons["add-gift.occasion"], expected: name)
    }

    /// A new gift sheet starts collapsed; the Occasion row only exists once Details is shown.
    private func showDetails() {
        let details = app.buttons["add-gift.details"]
        XCTAssertTrue(details.waitForExistence(timeout: timeout))
        if details.value as? String == "Shown" { return }
        details.tap()
        waitForValue(details, expected: "Shown")
    }

    private func saveGift(named name: String) {
        let save = app.buttons["add-gift.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        waitForDisappearance(save)
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: timeout))
    }

    // MARK: Ranking checks

    /// Opens From or To unfiltered, checks the first rows by position and by accessibility label,
    /// captures the picker and picks the top row (which closes it).
    private func verifyTopPeople(endpoint: String, expected: [String], screenshot: String) {
        app.buttons["add-gift.\(endpoint)"].tap()
        let query = app.textFields["person-picker.query"]
        XCTAssertTrue(query.waitForExistence(timeout: timeout))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person-picker.person.'"))
        XCTAssertTrue(waitWithOneRetry(timeout: timeout) { rows.count >= expected.count })
        let ordered = rowsByPosition(rows)
        for (index, name) in expected.enumerated() {
            XCTAssertTrue(
                ordered.indices.contains(index) && personLabel(ordered[index].label, is: name),
                "\(endpoint) picker row \(index + 1) should be \(name): \(ordered.map(\.label))")
        }
        // Both ranked rows sit at the top of the half-height sheet, so the capture shows them and the tap is safe.
        XCTAssertTrue(ordered[0].isHittable)
        attach(screenshot)
        ordered[0].tap()
        waitForDisappearance(query)
        waitForValue(app.buttons["add-gift.\(endpoint)"], expected: expected[0])
    }

    private func verifyTopOccasions(expected: [String], screenshot: String) {
        showDetails()
        app.buttons["add-gift.occasion"].tap()
        let prefix = "add-gift.occasion.option."
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        XCTAssertTrue(waitWithOneRetry(timeout: timeout) { rows.count >= expected.count })
        let ordered = rowsByPosition(rows)
        for (index, name) in expected.enumerated() {
            XCTAssertTrue(ordered.indices.contains(index), "Occasion picker has no row \(index + 1)")
            XCTAssertEqual(ordered[index].identifier, prefix + name)
            XCTAssertTrue(
                ordered[index].label.contains(name),
                "Occasion row \(index + 1) should be labelled \(name): \(ordered[index].label)")
        }
        XCTAssertTrue(ordered[0].isHittable)
        attach(screenshot)
        let top = app.buttons[prefix + expected[0]]
        ordered[0].tap()
        waitForDisappearance(top)
        waitForValue(app.buttons["add-gift.occasion"], expected: expected[0])
    }

    // MARK: Helpers

    /// Rows in the order they appear on screen, top first.
    private func rowsByPosition(_ query: XCUIElementQuery) -> [XCUIElement] {
        query.allElementsBoundByIndex.filter(\.exists).sorted { $0.frame.minY < $1.frame.minY }
    }

    private func personLabel(_ label: String, is name: String) -> Bool {
        label == name || label.hasSuffix(", \(name)")
    }

    private func personRows(named name: String) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'person-picker.person.' AND (label == %@ OR label ENDSWITH %@)",
                name,
                ", \(name)"
            ))
    }

    private func waitForDisappearance(_ element: XCUIElement) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func waitForValue(_ element: XCUIElement, expected: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func waitForKeyboardFocus(_ element: XCUIElement) {
        let focusedElement = app.descendants(matching: .any)
            .matching(identifier: element.identifier)
            .matching(NSPredicate(format: "hasKeyboardFocus == true"))
            .firstMatch
        // A tap during a sheet transition can be dropped on CI; re-tap once before failing.
        let focused = waitWithOneRetry(timeout: timeout, recover: { if element.exists { element.tap() } }) {
            focusedElement.exists
        }
        XCTAssertTrue(focused, "Text field did not acquire keyboard focus: \(element)")
    }

    /// Polls `condition` for `timeout`; if it is still false, runs `recover` once and polls for one more
    /// `timeout`. Bounded hardening for known CI Simulator flakes (slow snapshots, dropped taps).
    private func waitWithOneRetry(
        timeout: TimeInterval,
        interval: TimeInterval = 0.2,
        recover: () -> Void = {},
        until condition: () -> Bool
    ) -> Bool {
        for attempt in 1...2 {
            if attempt == 2 { recover() }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return false
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
