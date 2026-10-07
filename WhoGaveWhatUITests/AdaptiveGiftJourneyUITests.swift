import XCTest

final class AdaptiveGiftJourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 12
    private var giftName = "CI gift \(UUID().uuidString.prefix(8))"
    private var secondGiftName = "CI second gift \(UUID().uuidString.prefix(8))"
    private var giverName = "CI giver \(UUID().uuidString.prefix(8))"
    private var recipientName = "CI recipient \(UUID().uuidString.prefix(8))"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["KS_START"] = "app"
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: timeout))
    }

    func testAdaptiveGiftJourney() throws {
        attach("home-start")
        assertTabs()

        addGift(named: giftName, createPeople: true)
        XCTAssertTrue(app.staticTexts[giftName].waitForExistence(timeout: timeout))
        attach("gift-saved")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[giftName].waitForExistence(timeout: timeout))
        attach("gift-after-relaunch")

        addGift(named: secondGiftName, createPeople: false)
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
        XCTAssertTrue(app.staticTexts["People"].waitForExistence(timeout: timeout))
        attach("people")
        insights.tap()
        XCTAssertTrue(app.staticTexts["Insights"].waitForExistence(timeout: timeout))
        attach("insights")
        home.tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
    }

    private func addGift(named name: String, createPeople: Bool) {
        app.buttons["Add a gift"].tap()
        let giftNameField = app.textFields["add-gift.name"]
        XCTAssertTrue(giftNameField.waitForExistence(timeout: timeout))
        giftNameField.tap()
        giftNameField.typeText(name)
        app.buttons["add-gift.from"].tap()
        XCTAssertTrue(app.staticTexts["From"].waitForExistence(timeout: timeout))
        choosePerson(named: giverName, create: createPeople)
        app.buttons["add-gift.to"].tap()
        XCTAssertTrue(app.staticTexts["To"].waitForExistence(timeout: timeout))
        choosePerson(named: recipientName, create: createPeople)

        app.buttons["add-gift.details"].tap()
        XCTAssertTrue(app.textFields["add-gift.value"].waitForExistence(timeout: timeout))
        let value = app.textFields["add-gift.value"]
        value.tap()
        value.typeText("42")
        app.buttons["add-gift.scroll"].swipeUp()
        attach("details-value")

        app.buttons["add-gift.date"].tap()
        let calendar = app.otherElements["date-picker.calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: timeout))
        attach("calendar-current")
        // UICalendarView exposes its month as a native button/static text. A
        // swipe advances the real page and leaves the bottom attached sheet in
        // place, which is the layout we want the visual evidence to cover.
        calendar.swipeLeft()
        XCTAssertTrue(calendar.waitForExistence(timeout: timeout))
        attach("calendar-next-month")
        app.buttons["date-picker.today"].tap()

        XCTAssertTrue(app.buttons["add-gift.save"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["add-gift.save"].isEnabled)
        app.buttons["add-gift.save"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: timeout))
    }

    private func choosePerson(named name: String, create: Bool) {
        let query = app.textFields["person-picker.query"]
        XCTAssertTrue(query.waitForExistence(timeout: timeout))
        if create {
            query.tap()
            query.typeText(name)
            let add = app.buttons["person-picker.add"]
            XCTAssertTrue(add.waitForExistence(timeout: timeout))
            add.tap()
        } else {
            let row = app.staticTexts[name].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: timeout))
            row.tap()
        }
        XCTAssertTrue(app.buttons["add-gift.from"].exists || app.buttons["add-gift.to"].exists)
    }

    private func verifySettings() {
        app.buttons["Settings"].tap()
        let settings = app.otherElements["settings.screen"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        app.buttons["settings.currency"].tap()
        let currencyList = app.otherElements["settings.currency.list"]
        XCTAssertTrue(currencyList.waitForExistence(timeout: timeout))
        let usd = app.buttons["settings.currency.USD"]
        for _ in 0..<8 where !usd.exists { currencyList.swipeUp() }
        XCTAssertTrue(usd.waitForExistence(timeout: timeout))
        usd.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.buttons["settings.currency"].value as? String, "USD")
        attach("settings-usd")

        app.buttons["settings.third-party-licenses"].tap()
        let licenses = app.otherElements["settings.third-party-licenses.screen"]
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
}
