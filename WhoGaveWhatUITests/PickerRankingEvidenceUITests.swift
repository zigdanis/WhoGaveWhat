import XCTest

/// Temporary evidence for ranking the Add Gift pickers by recent use; removed after visual review.
final class PickerRankingEvidenceUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 12
    private var giftName = "CI ranking gift \(UUID().uuidString.prefix(8))"

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

    /// Saves a gift from the last seeded giver to a recipient who is not first in the seeded recipient list,
    /// with a non-default occasion, then checks that each picker lists those first in its own role.
    func testRecentlyUsedPickerOptionsComeFirst() throws {
        app.buttons["Add a gift"].tap()
        let field = app.textFields["add-gift.name"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText(giftName)

        chooseFirstRow(endpoint: "from", expected: nil, tapping: "dmitri")
        chooseFirstRow(endpoint: "to", expected: nil, tapping: "igor")
        app.buttons["add-gift.occasion"].tap()
        let wedding = app.buttons["add-gift.occasion.option.Wedding"]
        XCTAssertTrue(wedding.waitForExistence(timeout: timeout))
        wedding.tap()
        waitForDisappearance(wedding)

        let save = app.buttons["add-gift.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        waitForDisappearance(save)
        XCTAssertTrue(app.staticTexts[giftName].waitForExistence(timeout: timeout))

        app.buttons["Add a gift"].tap()
        XCTAssertTrue(app.buttons["add-gift.from"].waitForExistence(timeout: timeout))

        chooseFirstRow(endpoint: "from", expected: "dmitri", tapping: nil, screenshot: "picker-ranking-from")
        // The giver chosen above is not promoted in the recipient list: the recipient comes first.
        chooseFirstRow(endpoint: "to", expected: "igor", tapping: nil, screenshot: "picker-ranking-to")

        app.buttons["add-gift.occasion"].tap()
        let occasionRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'add-gift.occasion.option.'"))
        XCTAssertTrue(occasionRows.firstMatch.waitForExistence(timeout: timeout))
        let firstOccasion = topMost(occasionRows)
        XCTAssertEqual(firstOccasion?.identifier, "add-gift.occasion.option.Wedding")
        attach("picker-ranking-occasion")
        firstOccasion?.tap()

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: timeout))
    }

    /// Opens a person picker, optionally checks and captures it, and taps a row (the first one by default).
    private func chooseFirstRow(
        endpoint: String,
        expected: String?,
        tapping personID: String?,
        screenshot: String? = nil
    ) {
        app.buttons["add-gift.\(endpoint)"].tap()
        let query = app.textFields["person-picker.query"]
        XCTAssertTrue(query.waitForExistence(timeout: timeout))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person-picker.person.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: timeout))
        let first = topMost(rows)
        if let expected {
            XCTAssertEqual(first?.identifier, "person-picker.person.\(expected)")
        }
        if let screenshot { attach(screenshot) }
        let row = personID.map { app.buttons["person-picker.person.\($0)"] } ?? first
        XCTAssertTrue(row?.waitForExistence(timeout: timeout) ?? false)
        row?.tap()
        waitForDisappearance(query)
    }

    /// The element with the smallest vertical position, which is how the list is ordered on screen.
    private func topMost(_ query: XCUIElementQuery) -> XCUIElement? {
        query.allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY }
    }

    private func waitForDisappearance(_ element: XCUIElement) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
