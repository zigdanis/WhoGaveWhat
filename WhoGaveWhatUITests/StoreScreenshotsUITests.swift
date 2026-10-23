import XCTest

/// Captures the plain App Store screenshots from the Debug sample data.
///
/// The test only runs for `scripts/store-screenshots.py`, which forwards `KS_STORE_SCREENSHOTS=1`
/// and the store language (`KS_STORE_LOCALE=en-US|ru`) with xcodebuild's `TEST_RUNNER_` prefix.
/// In the normal suite it is skipped. Each screenshot is attached as `store-<locale>-NN-<slug>`.
final class StoreScreenshotsUITests: XCTestCase {
    /// The words the test taps or waits for, in the language of the store listing.
    private struct Listing {
        let id: String
        let appleLanguage: String
        let appleLocale: String
        let currency: String
        let homeTab: String
        let peopleTab: String
        let insightsTab: String
        let addGift: String
        let cancel: String
        let giftTitle: String
        let insightsTitle: String
        let giftName: String
        let viewpointName: String
        let giverName: String
        let recipientName: String
        let watchName: String
        /// Compared with the viewpoint: they exchanged a gift each way, so both flows have values.
        let compareName: String

        static let english = Listing(
            id: "en-US", appleLanguage: "en", appleLocale: "en_US", currency: "USD",
            homeTab: "Home", peopleTab: "People", insightsTab: "Insights",
            addGift: "Add a gift", cancel: "Cancel", giftTitle: "Gift", insightsTitle: "Insights",
            giftName: "Bouquet of roses", viewpointName: "Anton", giverName: "Anton", recipientName: "Marina",
            watchName: "Wristwatch", compareName: "Igor")

        static let russian = Listing(
            id: "ru", appleLanguage: "ru", appleLocale: "ru_RU", currency: "RUB",
            homeTab: "Главная", peopleTab: "Люди", insightsTab: "Аналитика",
            addGift: "Добавить подарок", cancel: "Отмена", giftTitle: "Подарок", insightsTitle: "Аналитика",
            giftName: "Букет роз", viewpointName: "Антон", giverName: "Антон", recipientName: "Марина",
            watchName: "Наручные часы", compareName: "Игорь")
    }

    private var app: XCUIApplication!
    private var listing = Listing.english
    private var shotNumber = 0
    private let timeout: TimeInterval = 12

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["KS_STORE_SCREENSHOTS"] == "1",
            "Store screenshots run only from scripts/store-screenshots.py")
        listing = try XCTUnwrap(
            [Listing.english, Listing.russian].first { $0.id == (environment["KS_STORE_LOCALE"] ?? "en-US") },
            "KS_STORE_LOCALE must be en-US or ru")
        continueAfterFailure = false
        app = XCUIApplication()
        // The currency argument overrides a code the app stored on an earlier launch, such as the other language's.
        app.launchArguments += [
            "-AppleLanguages", "(\(listing.appleLanguage))", "-AppleLocale", listing.appleLocale,
            "-preferredCurrencyCode", listing.currency
        ]
        // Debug-only seeded gifts and people; amounts follow the language's currency.
        app.launchEnvironment["KS_SAMPLE_DATA"] = "1"
        app.launchEnvironment["KS_START"] = "app"
        app.launchEnvironment["KS_RESET_SELF"] = "1"
        app.launchEnvironment["KS_APPEARANCE"] = "light"
        app.launchEnvironment["KS_CLOUD_ICONS"] = "stub"
        app.launchEnvironment["KS_CLOUD_ICON_CONSENT"] = "declined"
        app.launch()
        XCTAssertTrue(element(identifier: "appearance.light").waitForExistence(timeout: timeout))
        XCTAssertTrue(app.waitForTabButton(listing.homeTab, timeout: timeout).exists)
    }

    override func tearDown() {
        if testRun?.failureCount ?? 0 > 0, app != nil {
            attach("failure-screen")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "failure-accessibility-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        super.tearDown()
    }

    func testStoreScreenshots() {
        markAsViewpoint(listing.viewpointName)
        captureHome()
        captureAddGift()
        captureGiftDetails()
        captureHistoryOfPerson()
        captureInsights()
        captureCompare()
        capturePeople()
    }

    // MARK: Screens

    /// Anton becomes "You", so rows, balances and badges show the viewpoint's direction.
    private func markAsViewpoint(_ name: String) {
        selectTab(listing.peopleTab)
        let row = app.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        let meSwitch = app.switches["person-detail.is-me"]
        XCTAssertTrue(meSwitch.waitForExistence(timeout: timeout))
        // The switch sits at the trailing edge; the label area of a row toggle is not tappable.
        meSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.5)).tap()
        waitForValue(meSwitch, expected: "1")
        app.navigateBack()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: timeout))
    }

    private func captureHome() {
        selectTab(listing.homeTab)
        XCTAssertTrue(app.staticTexts[listing.giftName].waitForExistence(timeout: timeout))
        captureStoreShot("home")
    }

    /// A tidy form: icon from the name, giver and recipient chosen, keyboard up, nothing saved.
    private func captureAddGift() {
        app.buttons[listing.addGift].tap()
        let field = app.textFields["add-gift.name"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        choosePerson(listing.giverName, id: "anton", endpoint: "from")
        choosePerson(listing.recipientName, id: "marina", endpoint: "to")
        field.tap()
        waitForKeyboardFocus(field)
        field.typeText(listing.giftName)
        waitForValue(app.buttons["add-gift.emoji"], expected: "💐")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        captureStoreShot("add-gift")

        let save = app.buttons["add-gift.save"]
        app.buttons[listing.cancel].tap()
        waitForDisappearance(save)
        XCTAssertTrue(app.waitForTabButton(listing.homeTab, timeout: timeout).exists)
    }

    private func captureGiftDetails() {
        selectTab(listing.homeTab)
        let row = app.staticTexts[listing.watchName]
        scrollUntilHittable(row)
        row.tap()
        XCTAssertTrue(app.navigationBars[listing.giftTitle].waitForExistence(timeout: timeout))
        captureStoreShot("gift-details")
        app.navigateBack()
        XCTAssertTrue(app.staticTexts[listing.watchName].waitForExistence(timeout: timeout))
    }

    /// The viewpoint's own history: the richest person screen in the sample data.
    private func captureHistoryOfPerson() {
        selectTab(listing.peopleTab)
        let row = app.staticTexts[listing.viewpointName]
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        XCTAssertTrue(app.images["person-detail.hero"].waitForExistence(timeout: timeout))
        captureStoreShot("person")
        app.navigateBack()
        XCTAssertTrue(app.staticTexts[listing.viewpointName].waitForExistence(timeout: timeout))
    }

    private func captureInsights() {
        selectTab(listing.insightsTab)
        XCTAssertTrue(app.navigationBars[listing.insightsTitle].waitForExistence(timeout: timeout))
        XCTAssertTrue(element(identifier: "insights.balances").waitForExistence(timeout: timeout))
        captureStoreShot("insights")
    }

    /// The comparison card at the end of the Insights scroll view, with a person who gave and received.
    private func captureCompare() {
        let compare = element(identifier: "insights.compare")
        XCTAssertTrue(compare.waitForExistence(timeout: timeout))
        scrollToEnd(of: compare)
        let personB = app.buttons["insights.compare.b"]
        XCTAssertTrue(personB.isHittable)
        personB.tap()
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'insights.picker.person.' AND label CONTAINS %@", listing.compareName)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        waitForDisappearance(row)
        let chosen = NSPredicate(format: "label CONTAINS %@", listing.compareName)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: chosen, object: personB)], timeout: timeout),
            .completed)
        scrollToEnd(of: compare)
        XCTAssertTrue(app.buttons["insights.compare.a"].isHittable)
        XCTAssertTrue(personB.isHittable)
        captureStoreShot("compare")
    }

    private func scrollToEnd(of element: XCUIElement) {
        var previousMaxY: CGFloat?
        for _ in 0..<6 {
            let maxY = element.frame.maxY
            if maxY == previousMaxY { break }
            previousMaxY = maxY
            app.swipeUp()
            settle(0.8)
        }
    }

    private func capturePeople() {
        selectTab(listing.peopleTab)
        XCTAssertTrue(element(identifier: "people.you-badge").waitForExistence(timeout: timeout))
        captureStoreShot("people")
    }

    // MARK: Helpers

    /// Attaches the whole screen as `store-<locale>-NN-<slug>` after animations had time to settle.
    private func captureStoreShot(_ slug: String) {
        settle(1.2)
        shotNumber += 1
        attach("store-\(listing.id)-\(String(format: "%02d", shotNumber))-\(slug)")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// While scrolled down, the tab bar collapses to the current tab; scroll back up to expand it.
    private func selectTab(_ name: String) {
        for _ in 0..<3 where !app.waitForTabButton(name, timeout: 2).exists {
            app.swipeDown()
        }
        app.tabButton(name).tap()
    }

    /// Picks a sample person by searching for the name, so the row is on screen whatever the ranking.
    private func choosePerson(_ name: String, id: String, endpoint: String) {
        app.buttons["add-gift.\(endpoint)"].tap()
        let query = app.textFields["person-picker.query"]
        XCTAssertTrue(query.waitForExistence(timeout: timeout))
        query.tap()
        query.typeText(name)
        let row = app.buttons["person-picker.person.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        waitForDisappearance(query)
        waitForValue(app.buttons["add-gift.\(endpoint)"], expected: name)
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        for _ in 0..<4 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        XCTAssertTrue(element.isHittable, "\(element) is not on screen")
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
        let focused = app.descendants(matching: .any)
            .matching(identifier: element.identifier)
            .matching(NSPredicate(format: "hasKeyboardFocus == true"))
            .firstMatch
        // A tap during a sheet transition can be dropped on CI; re-tap once before failing.
        for attempt in 1...2 {
            if focused.waitForExistence(timeout: timeout) { return }
            if attempt == 1, element.exists { element.tap() }
        }
        XCTFail("Text field did not acquire keyboard focus: \(element)")
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
