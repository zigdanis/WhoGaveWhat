import XCTest

/// Temporary evidence: the Insights Person B picker lists the current choice first, then recent picks.
final class InsightsPickerRecentEvidenceUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 12
    private let suffix = String(UUID().uuidString.prefix(6))
    // "Zz" sorts them to the bottom of the alphabetical list, so moving up is visible.
    private var firstName: String { "Zz first \(suffix)" }
    private var secondName: String { "Zz second \(suffix)" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["KS_START"] = "app"
        app.launchEnvironment["KS_RESET_SELF"] = "1"
        app.launchEnvironment["KS_CLOUD_ICONS"] = "stub"
        app.launchEnvironment["KS_CLOUD_ICON_CONSENT"] = "declined"
        app.launch()
        XCTAssertTrue(app.waitForTabButton("Home", timeout: timeout).exists)
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

    func testPersonBPickerRaisesRecentPicks() {
        addPerson(firstName)
        addPerson(secondName)

        app.tabButton("Insights").tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: timeout))
        let personB = app.buttons["insights.compare.b"]
        for _ in 0..<4 where !(personB.exists && personB.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(personB.isHittable)

        personB.tap()
        XCTAssertTrue(pickerRow(0).waitForExistence(timeout: timeout))
        XCTAssertFalse(pickerRow(0).label.contains(firstName), pickerRow(0).label)
        attach("insights-picker-b-before")
        pick(firstName)

        personB.tap()
        XCTAssertTrue(pickerRow(0).waitForExistence(timeout: timeout))
        XCTAssertTrue(pickerRow(0).label.contains(firstName), pickerRow(0).label)
        attach("insights-picker-b-after-first-pick")
        pick(secondName)

        personB.tap()
        XCTAssertTrue(pickerRow(0).waitForExistence(timeout: timeout))
        XCTAssertTrue(pickerRow(0).label.contains(secondName), pickerRow(0).label)
        XCTAssertTrue(pickerRow(1).label.contains(firstName), pickerRow(1).label)
        attach("insights-picker-b-after-second-pick")
        pick(secondName)
        XCTAssertTrue(personB.label.contains(secondName), personB.label)
    }

    private func addPerson(_ name: String) {
        app.tabButton("People").tap()
        let addPerson = app.buttons["people.add-person"]
        XCTAssertTrue(addPerson.waitForExistence(timeout: timeout))
        addPerson.tap()
        let nameField = app.textFields["person-editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["person-editor.save"].tap()
        waitForDisappearance(nameField)
        // People is a lazy List and "Zz" sorts last, below people left by earlier tests.
        let row = app.staticTexts[name]
        for _ in 0..<8 where !row.waitForExistence(timeout: 1) {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
    }

    private var pickerRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'insights.picker.person.'"))
    }

    private func pickerRow(_ index: Int) -> XCUIElement {
        pickerRows.element(boundBy: index)
    }

    /// Taps the named row, scrolling the sheet when it sits below the visible part.
    private func pick(_ name: String) {
        let row = pickerRows.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        let list = app.scrollViews.containing(
            NSPredicate(format: "identifier BEGINSWITH 'insights.picker.person.'")
        ).firstMatch
        for _ in 0..<8 where !row.isHittable {
            list.swipeUp()
        }
        row.tap()
        waitForDisappearance(row)
    }

    private func waitForDisappearance(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
