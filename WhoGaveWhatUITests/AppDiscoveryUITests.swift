import XCTest

/// Runs only with --verify-app-names, because it changes a disposable Simulator's language preferences.
final class AppDiscoveryUITests: XCTestCase {
    private let app = XCUIApplication()
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let timeout: TimeInterval = 15
    private var shouldRestoreAppLanguage = false

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        continueAfterFailure = true
        defer {
            settings.terminate()
            app.terminate()
            super.tearDown()
        }
        if testRun?.failureCount ?? 0 > 0 {
            attach("app-discovery-failure")
            for (name, application) in [("app", app), ("settings", settings), ("springboard", springboard)] {
                let hierarchy = XCTAttachment(string: application.debugDescription)
                hierarchy.name = "app-discovery-\(name)-hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
        }
        // Keep the original failure evidence above intact before cleanup changes either app.
        guard shouldRestoreAppLanguage else { return }
        do {
            settings.activate()
            let englishChoice = settings.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] 'English'")
            )
            if !englishChoice.allElementsBoundByIndex.contains(where: { $0.isHittable }) {
                // Some iOS versions return to app settings after choosing a language.
                try tapSetting("Language", attemptLimit: 2)
            }
            try tapSetting("English", contains: true, attemptLimit: 2)
        } catch {
            let cleanup = XCTAttachment(string: "\(error)\n\n\(settings.debugDescription)")
            cleanup.name = "app-discovery-language-cleanup-failure"
            cleanup.lifetime = .keepAlways
            add(cleanup)
            XCTFail("Unable to restore the app's English language preference: \(error)")
        }
    }

    func testRussianAppLanguageAndBilingualSpotlightPreserveDraftAndOnboarding() throws {
        // Launch without AppleLanguages overrides: the app must follow its real Settings preference.
        app.launchEnvironment["KS_START"] = "app"
        app.launch()
        XCTAssertTrue(app.buttons["Add a gift"].waitForExistence(timeout: timeout))
        XCUIDevice.shared.press(.home)
        attach("home-screen-english")

        try setRussianAppLanguageWithEnglishSystem()
        app.launch()
        XCTAssertTrue(app.buttons["Добавить подарок"].waitForExistence(timeout: timeout))
        attach("russian-app-home")
        XCUIDevice.shared.press(.home)
        try showHomeAppIcon()
        attach("home-screen-russian-app")
        app.activate()

        let peopleTab = app.tabBars.buttons["Люди"]
        XCTAssertTrue(peopleTab.waitForExistence(timeout: timeout))
        peopleTab.tap()
        XCTAssertTrue(peopleTab.isSelected)
        XCTAssertTrue(app.buttons["people.add-person"].waitForExistence(timeout: timeout))
        try openSpotlightLauncher(query: "Who Gave", checkpoint: "spotlight-navigation-result")
        XCTAssertTrue(peopleTab.waitForExistence(timeout: timeout))
        XCTAssertTrue(peopleTab.isSelected, "Spotlight must preserve the selected People tab")
        XCTAssertTrue(app.buttons["people.add-person"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.textFields["add-gift.name"].exists)
        attach("spotlight-navigation-preserved")

        let homeTab = app.tabBars.buttons["Главная"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: timeout))
        homeTab.tap()
        XCTAssertTrue(homeTab.isSelected)
        XCTAssertTrue(app.buttons["Добавить подарок"].waitForExistence(timeout: timeout))
        app.buttons["Добавить подарок"].tap()
        let field = app.textFields["add-gift.name"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        let draft = "Spotlight draft \(UUID().uuidString.prefix(8))"
        field.typeText(draft)
        attach("spotlight-draft-before")
        for (query, checkpoint) in [("кто че", "spotlight-russian"), ("Who Gave", "spotlight-english")] {
            try openSpotlightLauncher(query: query, checkpoint: checkpoint)
            XCTAssertTrue(field.waitForExistence(timeout: timeout))
            XCTAssertEqual(field.value as? String, draft, "Spotlight must preserve the unsaved gift")
            XCTAssertTrue(app.buttons["add-gift.save"].exists)
            attach("\(checkpoint)-opened")
        }
        app.buttons["Отмена"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: timeout), .completed)
        XCTAssertTrue(homeTab.isSelected, "Cancelling the Spotlight-preserved draft must retain Home")
        attach("spotlight-draft-cancelled")

        // The UI launch shortcut never completes onboarding. SpringBoard must launch without that shortcut.
        app.terminate()
        app.launchEnvironment = [:]
        try openSpotlightLauncher(query: "кто че", checkpoint: "spotlight-cold-launch")
        XCTAssertTrue(app.buttons["Далее"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        attach("spotlight-cold-onboarding")
    }

    private func setRussianAppLanguageWithEnglishSystem() throws {
        settings.launch()
        attach("system-settings")
        try tapSetting("General")
        try tapSetting("Language & Region")
        attach("language-region-before")
        // The disposable device's secondary language is prepared before XCTest starts.
        // Editing the system language list here would terminate this test runner.
        let english = settings.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Reorder English'")
        ).firstMatch
        let russian = settings.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Reorder Russian' OR label BEGINSWITH 'Reorder Русский'")
        ).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: timeout))
        XCTAssertTrue(russian.waitForExistence(timeout: timeout))
        XCTAssertLessThan(english.frame.minY, russian.frame.minY, "English must remain the primary system language")
        attach("english-system-russian-secondary")

        try tapSetting("General")
        try tapSetting("Settings")
        try tapSetting("Apps")
        attach("settings-apps-list")
        try enterSettingsSearch("Who Gave")
        attach("settings-search-app")
        try tapSetting("Who Gave", contains: true)
        attach("app-settings-before")
        try tapSetting("Language")
        attach("app-language-picker")
        // Register cleanup before the mutation so a failed tap or later assertion cannot skip it.
        shouldRestoreAppLanguage = true
        try tapSetting("Russian", contains: true)
        attach("app-language-russian")
    }

    private func tapSetting(_ label: String, contains: Bool = false, attemptLimit: Int = 8) throws {
        let predicate = NSPredicate(format: contains ? "label CONTAINS[c] %@" : "label == %@", label)
        for _ in 0..<attemptLimit {
            for type in [XCUIElement.ElementType.cell, .button, .staticText] {
                let query = settings.descendants(matching: type).matching(predicate)
                _ = query.firstMatch.waitForExistence(timeout: 1)
                if let control = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                    control.tap()
                    return
                }
            }
            settings.swipeUp()
        }
        throw DiscoveryFailure.missingSettingsControl(label, settings.debugDescription)
    }

    private func enterSettingsSearch(_ text: String) throws {
        let nativeSearch = settings.searchFields.firstMatch
        let search = nativeSearch.waitForExistence(timeout: 3) ? nativeSearch : settings.textFields.firstMatch
        if !search.waitForExistence(timeout: timeout) {
            settings.swipeDown()
        }
        guard search.waitForExistence(timeout: timeout) else {
            throw DiscoveryFailure.missingSettingsControl("Search", settings.debugDescription)
        }
        search.tap()
        search.typeText(text)
    }

    private func showHomeAppIcon() throws {
        let icons = springboard.icons.matching(NSPredicate(format: "label == 'Who Gave' OR label == 'кто че'"))
        for _ in 0..<4 {
            if icons.allElementsBoundByIndex.contains(where: { $0.isHittable }) { return }
            springboard.swipeLeft()
        }
        throw DiscoveryFailure.missingHomeIcon(springboard.debugDescription)
    }

    private func openSpotlightLauncher(query: String, checkpoint: String) throws {
        XCUIDevice.shared.press(.home)
        // A Home-screen swipe opens the real Spotlight field; no result or index state is injected.
        springboard.swipeDown()
        let search = springboard.descendants(matching: .any)["SpotlightSearchField"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: timeout))
        search.tap()
        if let existing = search.value as? String, !existing.isEmpty {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        search.typeText(query)
        XCTAssertEqual(search.value as? String, query)
        let results = springboard.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier CONTAINS 'ResultCell' AND (label CONTAINS[c] 'кто че' OR label CONTAINS[c] 'Who Gave')"
            )
        )
        let deadline = Date().addingTimeInterval(60)
        repeat {
            if let result = results.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                attach(checkpoint)
                let observed = XCTAttachment(string: "query=\(query)\nresult=\(result.label)\nidentifier=\(result.identifier)")
                observed.name = "\(checkpoint)-observed-result"
                observed.lifetime = .keepAlways
                add(observed)
                result.tap()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout))
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        attach("\(checkpoint)-missing")
        throw DiscoveryFailure.missingSpotlightResult(query, springboard.debugDescription)
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private enum DiscoveryFailure: Error {
        case missingSettingsControl(String, String)
        case missingHomeIcon(String)
        case missingSpotlightResult(String, String)
    }
}
