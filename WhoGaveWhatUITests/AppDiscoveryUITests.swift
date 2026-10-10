import XCTest

/// Runs only with --verify-app-names, because it changes a disposable Simulator's language preferences.
final class AppDiscoveryUITests: XCTestCase {
    private let app = XCUIApplication()
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let spotlight = XCUIApplication(bundleIdentifier: "com.apple.Spotlight")
    private let timeout: TimeInterval = 15
    private var shouldRestoreAppLanguage = false
    private var spotlightQuery: String?

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
            attachSpotlightHierarchy("app-discovery-spotlight-hierarchy")
        }
        // Keep the original failure evidence above intact before cleanup changes either app.
        guard shouldRestoreAppLanguage else { return }
        do {
            // Dismiss a system search before starting a fresh, foreground Settings process.
            XCUIDevice.shared.press(.home)
            settings.launch()
            guard settings.wait(for: .runningForeground, timeout: timeout) else {
                throw DiscoveryFailure.settingsNotForeground
            }
            let englishChoice = settings.cells["English"]
            if !englishChoice.waitForExistence(timeout: 3) {
                // Settings can restore either its root, Apps list, or the app's detail page.
                if settings.navigationBars["Settings"].exists {
                    try tapSetting("Apps", attemptLimit: 2)
                }
                if settings.navigationBars["Apps"].exists {
                    try enterSettingsSearch("Who Gave")
                    try tapSetting("Who Gave", contains: true, attemptLimit: 2)
                }
                try tapSetting("Language", attemptLimit: 2)
            }
            try tapSetting("English", contains: true, attemptLimit: 2)
        } catch {
            let hierarchy = settings.state == .notRunning ? "Settings is not running" : settings.debugDescription
            let cleanup = XCTAttachment(string: "\(error)\n\n\(hierarchy)")
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
        try showHomeAppIcon()
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
                guard settings.state == .runningForeground else { throw DiscoveryFailure.settingsNotForeground }
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

    private var isAppLibraryVisible: Bool {
        let librarySearch = springboard.searchFields["dewey-search-field"]
        let libraryPods = springboard.otherElements["dewey-pod-view"]
        return (librarySearch.exists && librarySearch.isHittable) || (libraryPods.exists && libraryPods.isHittable)
    }

    private func regularHomeScreen() throws -> XCUIElement {
        // The first Home action exits the app; the second returns from the last page to Home.
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
        let icons = springboard.otherElements["Home screen icons"].firstMatch
        XCTAssertTrue(icons.waitForExistence(timeout: timeout))
        for _ in 0..<3 {
            // Home/page transitions briefly expose nonhittable icons and blurred snapshots.
            RunLoop.current.run(until: Date().addingTimeInterval(0.75))
            if !isAppLibraryVisible {
                XCTAssertTrue(icons.isHittable)
                return icons
            }
            // The observed dewey UI is App Library, including its alphabetical search.
            // Close that search, then move to a regular Home page before swiping down.
            XCUIDevice.shared.press(.home)
            icons.swipeRight()
        }
        throw DiscoveryFailure.appLibraryStillVisible(springboard.debugDescription)
    }

    private func showHomeAppIcon() throws {
        let home = try regularHomeScreen()
        let icons = springboard.icons.matching(NSPredicate(format: "label == 'Who Gave' OR label == 'кто че'"))
        for _ in 0..<4 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.75))
            // App Library icons cannot establish the app's Home-screen label.
            guard !isAppLibraryVisible else { break }
            if icons.allElementsBoundByIndex.contains(where: { $0.isHittable }) { return }
            home.swipeLeft()
        }
        throw DiscoveryFailure.missingHomeIcon(springboard.debugDescription)
    }

    private func openSpotlightLauncher(query: String, checkpoint: String) throws {
        spotlightQuery = query
        let home = try regularHomeScreen()
        // A regular Home-screen swipe opens Spotlight; App Library search is explicitly excluded.
        home.swipeDown()
        // Query the system search owner without launching or activating it ourselves.
        let isForeground = spotlight.wait(for: .runningForeground, timeout: timeout)
        attachSpotlightHierarchy("\(checkpoint)-owner")
        guard isForeground else { throw DiscoveryFailure.spotlightNotForeground }
        let search = spotlight.descendants(matching: .any)["SpotlightSearchField"].firstMatch
        guard search.waitForExistence(timeout: timeout), search.isHittable else {
            throw DiscoveryFailure.missingSpotlightSearchField(query)
        }
        search.tap()
        if let existing = search.value as? String, !existing.isEmpty {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        search.typeText(query)
        attachSpotlightHierarchy("\(checkpoint)-typed-query", typedValue: search.value as? String)
        XCTAssertEqual(search.value as? String, query)
        let results = spotlight.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier CONTAINS 'ResultCell' AND (label CONTAINS[c] 'кто че' OR label CONTAINS[c] 'Who Gave')"
            )
        )
        let deadline = Date().addingTimeInterval(60)
        repeat {
            if let result = results.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                attach(checkpoint)
                attachSpotlightHierarchy("\(checkpoint)-result", typedValue: search.value as? String)
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
        attachSpotlightHierarchy("\(checkpoint)-missing-result", typedValue: search.value as? String)
        throw DiscoveryFailure.missingSpotlightResult(query, spotlight.debugDescription)
    }

    private func attachSpotlightHierarchy(_ name: String, typedValue: String? = nil) {
        let state = spotlight.state
        let hierarchy = state == .notRunning ? "Spotlight is not running" : spotlight.debugDescription
        let observation = XCTAttachment(
            string: "bundle=com.apple.Spotlight\nstate=\(state.rawValue)\nrequestedQuery=\(spotlightQuery ?? "")\n"
                + "typedValue=\(typedValue ?? "")\n\n\(hierarchy)"
        )
        observation.name = name
        observation.lifetime = .keepAlways
        add(observation)
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private enum DiscoveryFailure: Error {
        case missingSettingsControl(String, String)
        case settingsNotForeground
        case appLibraryStillVisible(String)
        case missingHomeIcon(String)
        case spotlightNotForeground
        case missingSpotlightSearchField(String)
        case missingSpotlightResult(String, String)
    }
}
