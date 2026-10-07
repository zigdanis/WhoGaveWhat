import XCTest

final class AdaptiveGiftJourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 12
    private var giftName = "CI gift \(UUID().uuidString.prefix(8))"
    private var secondGiftName = "CI second gift \(UUID().uuidString.prefix(8))"
    private var giverName = "CI giver \(UUID().uuidString.prefix(8))"
    private var recipientName = "CI recipient \(UUID().uuidString.prefix(8))"
    private var personIDs: [String: String] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["KS_START"] = "app"
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

    func testAdaptiveGiftJourney() throws {
        attach("home-start")
        assertTabs()

        try addGift(named: giftName, createPeople: true)
        XCTAssertTrue(app.staticTexts[giftName].waitForExistence(timeout: timeout))
        attach("gift-saved")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[giftName].waitForExistence(timeout: timeout))
        attach("gift-after-relaunch")

        try addGift(named: secondGiftName, createPeople: false)
        XCTAssertTrue(app.staticTexts[secondGiftName].waitForExistence(timeout: timeout))
        verifySettings()
        assertTabs()
    }

    private func assertTabs() {
        let people = app.tabBars.buttons["People"]
        let insights = app.tabBars.buttons["Insights"]
        let home = app.tabBars.buttons["Home"]
        XCTAssertTrue(people.waitForExistence(timeout: timeout))
        XCTAssertTrue(insights.exists)
        XCTAssertTrue(home.exists)

        people.tap()
        XCTAssertTrue(people.isSelected)
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: timeout))
        attach("people")
        insights.tap()
        XCTAssertTrue(insights.isSelected)
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: timeout))
        attach("insights")
        home.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
    }

    private func addGift(named name: String, createPeople: Bool) throws {
        app.buttons["Add a gift"].tap()
        let giftNameField = app.textFields["add-gift.name"]
        XCTAssertTrue(giftNameField.waitForExistence(timeout: timeout))
        giftNameField.tap()
        giftNameField.typeText(name)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        attach("gift-compact-keyboard")
        app.buttons["add-gift.from"].tap()
        XCTAssertTrue(app.staticTexts["From"].waitForExistence(timeout: timeout))
        choosePerson(named: giverName, create: createPeople, endpoint: "from")
        app.buttons["add-gift.to"].tap()
        XCTAssertTrue(app.staticTexts["To"].waitForExistence(timeout: timeout))
        choosePerson(named: recipientName, create: createPeople, endpoint: "to")
        waitForDisappearance(app.keyboards.firstMatch)
        assertCompactSheetFrame()
        attach("gift-compact-dismissed")

        app.buttons["add-gift.details"].tap()
        XCTAssertTrue(app.textFields["add-gift.value"].waitForExistence(timeout: timeout))
        let value = app.textFields["add-gift.value"]
        value.tap()
        value.typeText("42")
        XCTAssertEqual(value.value as? String, "42")
        app.scrollViews["add-gift.scroll"].swipeUp()
        let save = app.buttons["add-gift.save"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            XCTAssertTrue(save.isHittable)
            XCTAssertLessThanOrEqual(save.frame.maxY, keyboard.frame.minY)
            attach("details-value-keyboard")
        } else {
            XCTAssertTrue(save.isHittable)
            attach("details-value-keyboard-dismissed")
        }
        attach("details-value")

        app.buttons["add-gift.date"].tap()
        let calendar = app.otherElements["date-picker.calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: timeout))
        let firstMonth = try monthHeading(in: calendar)
        let firstWeekCount = weekCount(for: firstMonth)
        XCTAssertGreaterThan(firstWeekCount, 0)
        assertCompactSheetFrame()
        attach("calendar-\(firstWeekCount)-weeks")
        var nextWeekCount = firstWeekCount
        var previousMonth = firstMonth
        for _ in 0..<12 where nextWeekCount == firstWeekCount {
            let next = calendar.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'next month' OR label CONTAINS[c] 'next'")).firstMatch
            if next.exists && next.isHittable { next.tap() } else { calendar.swipeLeft() }
            let nextMonth = try monthHeading(in: calendar, excluding: previousMonth)
            previousMonth = nextMonth
            nextWeekCount = weekCount(for: nextMonth)
        }
        XCTAssertGreaterThan(nextWeekCount, 0)
        XCTAssertNotEqual(nextWeekCount, firstWeekCount)
        assertCompactSheetFrame()
        attach("calendar-\(nextWeekCount)-weeks")
        let expectedPreviousMonth = adjacentMonth(from: previousMonth, offset: -1)
        let previous = calendar.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'previous month' OR label CONTAINS[c] 'previous'")).firstMatch
        if previous.exists && previous.isHittable { previous.tap() } else { calendar.swipeRight() }
        let reversedMonth = try monthHeading(in: calendar, excluding: previousMonth)
        XCTAssertEqual(reversedMonth, expectedPreviousMonth)
        assertCompactSheetFrame()
        attach("calendar-reverse")
        app.buttons["date-picker.today"].tap()

        XCTAssertTrue(app.buttons["add-gift.save"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["add-gift.save"].isEnabled)
        app.buttons["add-gift.save"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["add-gift.save"].exists)
    }

    private func choosePerson(named name: String, create: Bool, endpoint: String) {
        let query = app.textFields["person-picker.query"]
        XCTAssertTrue(query.waitForExistence(timeout: timeout))
        if create {
            query.tap()
            query.typeText(name)
            let add = app.buttons["person-picker.add"]
            XCTAssertTrue(add.waitForExistence(timeout: timeout))
            XCTAssertTrue(add.isEnabled)
            attach("person-picker-before-add-\(endpoint)")
            attachHierarchy("person-picker-before-add-\(endpoint)", selectedValue: query.value as? String)
            add.tap()
        } else {
            let matchingRows = personRows(named: name)
            XCTAssertEqual(matchingRows.count, 1)
            let originalID = matchingRows[0].identifier
            personIDs[name] = originalID
            query.tap()
            query.typeText(name)
            let add = app.buttons["person-picker.add"]
            XCTAssertTrue(add.waitForExistence(timeout: timeout))
            XCTAssertTrue(add.isEnabled)
            attach("person-picker-before-duplicate-add-\(endpoint)")
            attachHierarchy("person-picker-before-duplicate-add-\(endpoint)", selectedValue: query.value as? String)
            add.tap()
            waitForDisappearance(query)

            app.buttons["add-gift.\(endpoint)"].tap()
            XCTAssertTrue(app.textFields["person-picker.query"].waitForExistence(timeout: timeout))
            let reopenedRows = personRows(named: name)
            XCTAssertEqual(reopenedRows.count, 1)
            XCTAssertEqual(reopenedRows[0].identifier, originalID)
            reopenedRows[0].tap()
        }
        waitForDisappearance(app.textFields["person-picker.query"])
        let endpointElement = app.buttons["add-gift.\(endpoint)"]
        waitForValue(endpointElement, expected: name)
        XCTAssertEqual(endpointElement.value as? String, name)
        attach("form-after-person-add-\(endpoint)")
        attachHierarchy("form-after-person-add-\(endpoint)", selectedValue: endpointElement.value as? String)
    }

    private func verifySettings() {
        app.buttons["Settings"].tap()
        let settings = element(identifier: "settings.screen")
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        let initialCurrency = app.buttons["settings.currency"].value as? String
        XCTAssertNotNil(initialCurrency)
        app.buttons["settings.currency"].tap()
        let currencyList = element(identifier: "settings.currency.list")
        XCTAssertTrue(currencyList.waitForExistence(timeout: timeout))
        let targetCode = initialCurrency == "AUD" ? "AFN" : "AUD"
        XCTAssertNotEqual(targetCode, initialCurrency)
        let target = app.buttons["settings.currency.\(targetCode)"]
        XCTAssertTrue(target.waitForExistence(timeout: timeout))
        target.tap()
        XCTAssertTrue(app.navigationBars.buttons["Settings"].waitForExistence(timeout: timeout))
        app.navigationBars.buttons["Settings"].tap()
        XCTAssertEqual(app.buttons["settings.currency"].value as? String, targetCode)
        attach("settings-currency")

        app.buttons["settings.third-party-licenses"].tap()
        let licenses = element(identifier: "settings.third-party-licenses.screen")
        XCTAssertTrue(licenses.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Archivo'")).firstMatch.waitForExistence(timeout: timeout))
        attach("licenses")
        XCTAssertTrue(app.navigationBars.buttons["Settings"].waitForExistence(timeout: timeout))
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: timeout))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertCompactSheetFrame() {
        let grabbers = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Sheet Grabber'"))
        let deadline = Date().addingTimeInterval(timeout)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        let bottom = window.frame.maxY
        while Date() < deadline {
            let visibleGrabbers = grabbers.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            if let grabber = visibleGrabbers.max(by: { $0.frame.minY < $1.frame.minY }) {
                let top = grabber.frame.minY
                if top > bottom * 0.25 && top < bottom * 0.8 { return }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("No settled frontmost Sheet Grabber in measured compact range: \(grabbers.debugDescription)")
    }

    private func personRows(named name: String) -> [XCUIElement] {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'person-picker.person.'"))
            .allElementsBoundByIndex
            .filter { row in
                row.descendants(matching: .staticText)
                    .matching(NSPredicate(format: "label == %@", name))
                    .firstMatch
                    .exists
            }
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

    private func attachHierarchy(_ name: String, selectedValue: String?) {
        let value = selectedValue ?? "<nil>"
        let attachment = XCTAttachment(string: "selectedValue=\(value)\n\n\(app.debugDescription)")
        attachment.name = "\(name)-hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func monthHeading(in calendar: XCUIElement, excluding: String? = nil) throws -> String {
        let predicate = NSPredicate(format: "label MATCHES[c] '^[A-Z][a-z]+ [0-9]{4}$'")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let headings = calendar.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
            if let heading = headings.first(where: { $0.label != excluding }) { return heading.label }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTFail(calendar.debugDescription)
        return ""
    }

    private func weekCount(for month: String) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMMM yyyy"
        guard let date = formatter.date(from: month) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        let range = calendar.range(of: .day, in: .month, for: date)!
        let offset = calendar.component(.weekday, from: date) - calendar.firstWeekday
        return (offset + range.count + 6) / 7
    }

    private func adjacentMonth(from month: String, offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MMMM yyyy"
        guard let date = formatter.date(from: month),
            let adjacent = formatter.calendar.date(byAdding: .month, value: offset, to: date)
        else { return "" }
        return formatter.string(from: adjacent)
    }
}
