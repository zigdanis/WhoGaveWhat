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
        verifyPersonProfileJourney()

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
        let save = app.buttons["add-gift.save"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        let keyboard = app.keyboards.firstMatch
        assertSaveReachableAboveKeyboard(save, keyboard: keyboard)
        attach("details-value")

        app.buttons["add-gift.date"].tap()
        let calendar = app.otherElements["date-picker.calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: timeout))
        let firstMonth = try monthHeading(in: calendar)
        let expectedMonth = DateFormatter()
        expectedMonth.locale = Locale(identifier: "en_US")
        expectedMonth.calendar = Calendar(identifier: .gregorian)
        expectedMonth.dateFormat = "MMMM yyyy"
        XCTAssertEqual(firstMonth, expectedMonth.string(from: Date()))
        XCTAssertTrue(app.buttons["date-picker.today"].exists)
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.timeZone = .autoupdatingCurrent
        dayFormatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(calendar.value as? String, "selected-day:\(dayFormatter.string(from: Date()))")
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

    private func verifyPersonProfileJourney() {
        let people = app.tabBars.buttons["People"]
        people.tap()
        let personRow = app.staticTexts[giverName]
        XCTAssertTrue(personRow.waitForExistence(timeout: timeout))
        personRow.tap()
        let detailNavigationBar = app.navigationBars[giverName]
        XCTAssertTrue(detailNavigationBar.waitForExistence(timeout: timeout))
        let hero = app.images["person-detail.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: timeout))
        let displayedNames = app.staticTexts.matching(NSPredicate(format: "label == %@", giverName))
        XCTAssertEqual(displayedNames.count, 1)
        attach("person-detail")

        app.buttons["Edit name"].tap()
        XCTAssertTrue(app.navigationBars["Edit name"].waitForExistence(timeout: timeout))
        let choosePhoto = app.buttons["Choose photo"]
        XCTAssertTrue(choosePhoto.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        attach("person-editor")

        choosePhoto.tap()
        let pickerNavigationBar = app.navigationBars["Photos"]
        XCTAssertTrue(pickerNavigationBar.waitForExistence(timeout: 60))
        let photoImages = app.images.matching(NSPredicate(format: "label BEGINSWITH[c] 'Photo,'"))
        let photoDeadline = Date().addingTimeInterval(60)
        while !photoImages.firstMatch.exists && Date() < photoDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(photoImages.firstMatch.exists)
        attach("person-photo-picker")
        let firstPhoto = photoImages.firstMatch
        let windowFrame = app.windows.firstMatch.frame
        // Photo tiles are visible in CI but reported as non-hittable by XCTest.
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: firstPhoto.frame.midX / windowFrame.width,
                dy: firstPhoto.frame.midY / windowFrame.height
            )
        ).tap()
        let editorNavigationBar = app.navigationBars["Edit name"]
        XCTAssertTrue(editorNavigationBar.waitForExistence(timeout: timeout))
        let editorReturnDeadline = Date().addingTimeInterval(timeout)
        while !editorNavigationBar.isHittable && Date() < editorReturnDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(editorNavigationBar.isHittable)
        XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: timeout))
        attach("person-editor-selected-photo")
        app.buttons["Save"].tap()
        waitForDisappearance(editorNavigationBar)
        XCTAssertTrue(detailNavigationBar.waitForExistence(timeout: timeout))
        let detailReturnDeadline = Date().addingTimeInterval(timeout)
        while !detailNavigationBar.isHittable && Date() < detailReturnDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(detailNavigationBar.isHittable)
        XCTAssertTrue(hero.waitForExistence(timeout: timeout))
        attach("person-detail-selected-photo")

        app.buttons["Edit name"].tap()
        XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.navigationBars["Edit name"].buttons["Cancel"].tap()
        app.navigationBars[giverName].buttons["BackButton"].tap()
        app.tabBars.buttons["Home"].tap()
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
            if matchingRows.count != 1 {
                attachPersonRowDiagnostics("before-duplicate-add-\(endpoint)", name: name, rows: matchingRows)
            }
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
            if reopenedRows.count != 1 {
                attachPersonRowDiagnostics("after-duplicate-add-\(endpoint)", name: name, rows: reopenedRows)
            }
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
        let currencyNavigationBar = app.navigationBars["Currency"]
        XCTAssertTrue(currencyNavigationBar.waitForExistence(timeout: timeout))
        let currencyBack = currencyNavigationBar.buttons["BackButton"]
        XCTAssertTrue(currencyBack.waitForExistence(timeout: timeout))
        currencyBack.tap()
        XCTAssertEqual(app.buttons["settings.currency"].value as? String, targetCode)
        attach("settings-currency")

        app.buttons["settings.third-party-licenses"].tap()
        let licenses = element(identifier: "settings.third-party-licenses.screen")
        XCTAssertTrue(licenses.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Archivo'")).firstMatch.waitForExistence(timeout: timeout))
        attach("licenses")
        let licensesNavigationBar = app.navigationBars["Third-party licenses"]
        XCTAssertTrue(licensesNavigationBar.waitForExistence(timeout: timeout))
        let licensesBack = licensesNavigationBar.buttons["BackButton"]
        XCTAssertTrue(licensesBack.waitForExistence(timeout: timeout))
        licensesBack.tap()
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

    private func assertSaveReachableAboveKeyboard(_ save: XCUIElement, keyboard: XCUIElement) {
        let scroll = app.scrollViews["add-gift.scroll"]
        for attempt in 0..<3 {
            if !keyboard.exists {
                XCTAssertTrue(save.isHittable)
                attach("details-value-keyboard-dismissed")
                return
            }
            if save.isHittable && save.frame.maxY <= keyboard.frame.minY {
                attach("details-value-keyboard")
                return
            }
            let window = app.windows.firstMatch
            let visibleBottom = keyboard.frame.minY - 16
            let visibleFrame = scroll.frame.intersection(
                CGRect(
                    x: scroll.frame.minX,
                    y: scroll.frame.minY,
                    width: scroll.frame.width,
                    height: max(0, visibleBottom - scroll.frame.minY)
                )
            )
            guard visibleFrame.height > 40 else {
                XCTFail("No usable scroll area above keyboard: scroll=\(scroll.frame), keyboard=\(keyboard.frame)")
                return
            }
            let startY = visibleFrame.minY + visibleFrame.height * 0.8
            let endY = visibleFrame.minY + visibleFrame.height * 0.2
            let start = window.coordinate(
                withNormalizedOffset: CGVector(
                    dx: (visibleFrame.midX - window.frame.minX) / window.frame.width,
                    dy: (startY - window.frame.minY) / window.frame.height
                ))
            let end = window.coordinate(
                withNormalizedOffset: CGVector(
                    dx: (visibleFrame.midX - window.frame.minX) / window.frame.width,
                    dy: (endY - window.frame.minY) / window.frame.height
                ))
            start.press(forDuration: 0.05, thenDragTo: end)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if attempt == 2 { break }
        }

        if !keyboard.exists {
            XCTAssertTrue(save.isHittable)
            attach("details-value-keyboard-dismissed")
        } else if save.isHittable && save.frame.maxY <= keyboard.frame.minY {
            attach("details-value-keyboard")
        } else {
            XCTFail("Save remains covered by keyboard: save=\(save.frame), keyboard=\(keyboard.frame)")
        }
    }

    private func personRows(named name: String) -> [XCUIElement] {
        app.buttons
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH 'person-picker.person.' AND (label == %@ OR label ENDSWITH %@)",
                    name,
                    ", \(name)"
                )
            )
            .allElementsBoundByIndex
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

    private func attachPersonRowDiagnostics(_ name: String, name personName: String, rows: [XCUIElement]) {
        let candidates = rows.enumerated().map { index, row in
            "candidate[\(index)] identifier=\(row.identifier) label=\(row.label) frame=\(row.frame) hittable=\(row.isHittable)"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(
            string: "personName=\(personName)\n\(candidates)\n\nquery=\(app.buttons.debugDescription)\n\n\(app.debugDescription)"
        )
        attachment.name = "person-row-\(name)"
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
