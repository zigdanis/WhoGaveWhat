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
        app.launchEnvironment["KS_SPOTLIGHT_DIAGNOSTICS"] = "1"
        app.launch()
        observeLauncherQueriesWhileForeground("discovery-english")
        XCTAssertTrue(app.buttons["Add a gift"].waitForExistence(timeout: timeout))
        try showHomeAppIcon()
        attach("home-screen-english")

        try setRussianAppLanguageWithEnglishSystem()
        app.launch()
        observeLauncherQueriesWhileForeground("discovery-russian")
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

    private func observeLauncherQueriesWhileForeground(_ checkpoint: String) {
        guard app.launchEnvironment["KS_SPOTLIGHT_DIAGNOSTICS"] == "1" else { return }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: timeout))
        attach("\(checkpoint)-foreground-before")
        let before = XCTAttachment(string: app.debugDescription)
        before.name = "\(checkpoint)-foreground-before-hierarchy"
        before.lifetime = .keepAlways
        add(before)
        // Keep the existing 10-second exact query and two 10-second user queries active.
        // Home/background suspension must not confound this diagnostic batch.
        let deadline = Date().addingTimeInterval(35)
        repeat {
            XCTAssertEqual(app.state, .runningForeground, "Launcher diagnostics require continuous foreground residency")
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.25)))
        } while Date() < deadline
        XCTAssertEqual(app.state, .runningForeground)
        attach("\(checkpoint)-foreground-after")
        let after = XCTAttachment(string: app.debugDescription)
        after.name = "\(checkpoint)-foreground-after-hierarchy"
        after.lifetime = .keepAlways
        add(after)
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
        try tapSetting("Search")
        RunLoop.current.run(until: Date().addingTimeInterval(0.75))
        attach("app-search-visibility")
        let visibility = XCTAttachment(string: settings.debugDescription)
        visibility.name = "app-search-visibility-hierarchy"
        visibility.lifetime = .keepAlways
        add(visibility)
        try tapSetting("Who Gave")
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
        try clearSpotlightQuery(search)
        try selectSpotlightKeyboard(for: query, checkpoint: checkpoint)
        search.typeText(query)
        attachSpotlightHierarchy("\(checkpoint)-typed-query", typedValue: search.value as? String)
        XCTAssertEqual(search.value as? String, query)
        let results = spotlight.descendants(matching: .any).matching(
            NSPredicate(
                format:
                    "identifier CONTAINS 'ResultCell' AND NOT (label CONTAINS[c] 'WhoGaveWhatUITests-Runner') AND (label CONTAINS[c] 'кто че' OR label CONTAINS[c] 'Who Gave')"
            )
        )
        let deadline = Date().addingTimeInterval(60)
        var scrolls = 0
        repeat {
            let appResults = results.allElementsBoundByIndex.filter(isAppLauncherResult)
            if let result = appResults.first(where: { $0.isHittable }) {
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
            if !appResults.isEmpty, scrolls < 3, Date() < deadline {
                let collection = spotlight.collectionViews.firstMatch
                guard collection.exists, collection.isHittable else {
                    throw DiscoveryFailure.missingSpotlightResultsCollection
                }
                // Choose a contiguous results area outside both the keyboard and search field.
                let collectionFrame = collection.frame
                var visibleTop = collectionFrame.minY
                var visibleBottom = collectionFrame.maxY
                let keyboard = spotlight.keyboards.firstMatch
                if keyboard.exists {
                    visibleBottom = min(visibleBottom, keyboard.frame.minY)
                }
                let searchFrame = search.frame
                if searchFrame.minY < visibleBottom, searchFrame.maxY > visibleTop {
                    let aboveSearch = searchFrame.minY - visibleTop
                    let belowSearch = visibleBottom - searchFrame.maxY
                    if aboveSearch >= belowSearch {
                        visibleBottom = searchFrame.minY
                    } else {
                        visibleTop = searchFrame.maxY
                    }
                }
                guard visibleBottom - visibleTop > 124 else {
                    throw DiscoveryFailure.missingSpotlightResultsCollection
                }
                let startY = visibleBottom - collectionFrame.minY - 24
                let endY = max(visibleTop - collectionFrame.minY + 40, startY - 240)
                guard startY > endY else { throw DiscoveryFailure.missingSpotlightResultsCollection }
                let origin = collection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                let start = origin.withOffset(CGVector(dx: 0, dy: startY))
                let end = origin.withOffset(CGVector(dx: 0, dy: endY))
                scrolls += 1
                attach("\(checkpoint)-scroll-\(scrolls)-before")
                attachSpotlightHierarchy("\(checkpoint)-scroll-\(scrolls)-before", typedValue: search.value as? String)
                start.press(forDuration: 0.1, thenDragTo: end)
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.5)))
                attach("\(checkpoint)-scroll-\(scrolls)-after")
                attachSpotlightHierarchy("\(checkpoint)-scroll-\(scrolls)-after", typedValue: search.value as? String)
                XCTAssertEqual(search.value as? String, query, "Scrolling must preserve the Spotlight query")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        attach("\(checkpoint)-missing")
        attachSpotlightHierarchy("\(checkpoint)-missing-result", typedValue: search.value as? String)
        let failedHierarchy = spotlight.debugDescription
        if query == "Who Gave", spotlight.state == .runningForeground, search.isHittable {
            // Probe the localized title to distinguish missing indexing from missing English aliases.
            // This diagnostic never taps a result or satisfies the failed English acceptance check.
            spotlightQuery = "кто че"
            do {
                try clearSpotlightQuery(search)
                try selectSpotlightKeyboard(for: "кто че", checkpoint: "\(checkpoint)-diagnostic-russian-title")
                search.typeText("кто че")
                guard search.value as? String == "кто че" else {
                    throw DiscoveryFailure.mismatchedDiagnosticQuery("кто че", String(describing: search.value))
                }
                let diagnosticDeadline = Date().addingTimeInterval(30)
                while !results.allElementsBoundByIndex.contains(where: { $0.isHittable }), Date() < diagnosticDeadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                }
            } catch {
                let failure = XCTAttachment(string: "\(error)")
                failure.name = "\(checkpoint)-diagnostic-query-failure"
                failure.lifetime = .keepAlways
                add(failure)
            }
            attach("\(checkpoint)-diagnostic-russian-title")
            attachSpotlightHierarchy("\(checkpoint)-diagnostic-russian-title", typedValue: search.value as? String)
            if search.value as? String == "кто че", results.firstMatch.exists {
                // Compare aliases only after the localized item is actually retrievable.
                // Offscreen rows count as retrieval evidence here; these probes never open them.
                let pairedDeadline = Date().addingTimeInterval(90)
                let englishObserved = observePairedSpotlightQuery(
                    "Who Gave", search: search, results: results,
                    checkpoint: "\(checkpoint)-diagnostic-paired-english", retrievalTimeout: 30,
                    waitDeadline: pairedDeadline
                )
                if englishObserved {
                    observePairedSpotlightQuery(
                        "кто че", search: search, results: results,
                        checkpoint: "\(checkpoint)-diagnostic-paired-russian", retrievalTimeout: 15,
                        waitDeadline: pairedDeadline
                    )
                } else {
                    let skipped = XCTAttachment(string: "outcome=skipped\nreason=paired English probe inconclusive or failed")
                    skipped.name = "\(checkpoint)-diagnostic-paired-russian-skipped"
                    skipped.lifetime = .keepAlways
                    add(skipped)
                }
            } else {
                let skipped = XCTAttachment(
                    string: "outcome=skipped\nreason=localized launcher row not confirmed\n"
                        + "typedValue=\(String(describing: search.value))\nresultExists=\(results.firstMatch.exists)"
                )
                skipped.name = "\(checkpoint)-diagnostic-paired-skipped"
                skipped.lifetime = .keepAlways
                add(skipped)
            }
        }
        if spotlight.state == .runningForeground, search.isHittable {
            // A built-in app provides a control for the system app catalog, without opening it.
            spotlightQuery = "Calendar"
            do {
                try clearSpotlightQuery(search)
                try selectSpotlightKeyboard(for: "Calendar", checkpoint: "\(checkpoint)-diagnostic-calendar")
                search.typeText("Calendar")
                guard search.value as? String == "Calendar" else {
                    throw DiscoveryFailure.mismatchedDiagnosticQuery("Calendar", String(describing: search.value))
                }
                let calendar = spotlight.cells.matching(
                    NSPredicate(format: "identifier CONTAINS 'GridCell' AND label == 'Calendar'")
                ).firstMatch
                let calendarIcon = calendar.icons["Calendar"].firstMatch
                let topHit = spotlight.otherElements.matching(
                    NSPredicate(format: "identifier CONTAINS 'SectionHeader' AND identifier CONTAINS 'Title:Top Hit'")
                ).firstMatch
                let controlDeadline = Date().addingTimeInterval(30)
                while !(topHit.exists && calendar.exists && calendar.isHittable && calendarIcon.exists), Date() < controlDeadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                }
            } catch {
                let failure = XCTAttachment(string: "\(error)")
                failure.name = "\(checkpoint)-diagnostic-calendar-failure"
                failure.lifetime = .keepAlways
                add(failure)
            }
            attach("\(checkpoint)-diagnostic-calendar")
            attachSpotlightHierarchy("\(checkpoint)-diagnostic-calendar", typedValue: search.value as? String)
        }
        throw DiscoveryFailure.missingSpotlightResult(query, failedHierarchy)
    }

    private func isAppLauncherResult(_ result: XCUIElement) -> Bool {
        guard !result.label.contains("WhoGaveWhatUITests-Runner") else { return false }
        if result.icons.matching(NSPredicate(format: "label == 'Who Gave' OR label == 'кто че'")).firstMatch.exists {
            return true
        }
        // Indexed launcher rows belong to the app's own section, rather than Websites.
        guard let section = result.identifier.components(separatedBy: ",").first(where: { $0.hasPrefix("Section:") }) else {
            return false
        }
        // Spotlight can promote this indexed launcher into Top Hit without exposing an AX icon.
        let indexedLauncherLabel = "кто че, Who Gave; Who Gave What; WhoGaveWhat; кто че; кто чё, Who Gave"
        if result.label.precomposedStringWithCanonicalMapping == indexedLauncherLabel,
            spotlight.otherElements["Identifier:SectionHeader,\(section),Title:Top Hit"].firstMatch.exists
        {
            return true
        }
        let header = spotlight.otherElements.matching(
            NSPredicate(
                format: "identifier == %@ OR identifier == %@",
                "Identifier:SectionHeader,\(section),Title:Who Gave",
                "Identifier:SectionHeader,\(section),Title:кто че"
            )
        ).firstMatch
        return header.exists
    }

    @discardableResult
    private func observePairedSpotlightQuery(
        _ query: String, search: XCUIElement, results: XCUIElementQuery,
        checkpoint: String, retrievalTimeout: TimeInterval, waitDeadline: Date
    ) -> Bool {
        let startedAt = Date()
        attach("\(checkpoint)-start")
        attachSpotlightHierarchy("\(checkpoint)-start", typedValue: search.value as? String)
        spotlightQuery = query
        var outcome: String
        var queryObserved = false
        var phase = "clear"
        do {
            guard Date() < waitDeadline else { throw DiscoveryFailure.diagnosticWaitBudgetExpired }
            guard spotlight.state == .runningForeground, search.exists, search.isHittable else {
                throw DiscoveryFailure.missingSpotlightSearchField(query)
            }
            try clearSpotlightQuery(search, waitDeadline: waitDeadline)
            phase = "empty-results"
            attachSpotlightHierarchy("\(checkpoint)-empty-query", typedValue: search.value as? String)
            let emptyDeadline = min(Date().addingTimeInterval(5), waitDeadline)
            while results.firstMatch.exists, Date() < emptyDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
            guard !results.firstMatch.exists else { throw DiscoveryFailure.diagnosticPriorResultNotCleared }
            phase = "keyboard-and-focus"
            guard Date() < waitDeadline else { throw DiscoveryFailure.diagnosticWaitBudgetExpired }
            try selectSpotlightKeyboard(for: query, checkpoint: checkpoint, waitDeadline: waitDeadline)
            phase = "type"
            guard Date() < waitDeadline else { throw DiscoveryFailure.diagnosticWaitBudgetExpired }
            search.typeText(query)
            guard search.value as? String == query else {
                throw DiscoveryFailure.mismatchedDiagnosticQuery(query, String(describing: search.value))
            }
            attachSpotlightHierarchy("\(checkpoint)-typed-query", typedValue: search.value as? String)
            phase = "retrieval"
            let deadline = min(Date().addingTimeInterval(retrievalTimeout), waitDeadline)
            RunLoop.current.run(until: min(Date().addingTimeInterval(0.75), deadline))
            while !results.firstMatch.exists, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
            if let result = results.allElementsBoundByIndex.first {
                outcome = "outcome=exists\nresult=\(result.label)\nidentifier=\(result.identifier)\nhittable=\(result.isHittable)"
            } else if Date() >= waitDeadline {
                outcome = "outcome=inconclusive\nreason=paired wait budget expired\nphase=\(phase)"
            } else {
                outcome = "outcome=not-found"
            }
            queryObserved = Date() < waitDeadline
        } catch DiscoveryFailure.diagnosticPriorResultNotCleared {
            outcome = "outcome=inconclusive\nphase=\(phase)\nreason=prior launcher row persisted after clearing query"
        } catch {
            // Secondary probes cannot replace the original English acceptance failure.
            let status = Date() >= waitDeadline ? "inconclusive" : "failure"
            outcome = "outcome=\(status)\nphase=\(phase)\nerror=\(error)"
        }
        attach("\(checkpoint)-end")
        attachSpotlightHierarchy("\(checkpoint)-end", typedValue: search.value as? String)
        let observation = XCTAttachment(
            string: "query=\(query)\nretrievalTimeout=\(retrievalTimeout)\n"
                + "startedAt=\(startedAt.timeIntervalSince1970)\nfinishedAt=\(Date().timeIntervalSince1970)\n\(outcome)"
        )
        observation.name = "\(checkpoint)-outcome"
        observation.lifetime = .keepAlways
        add(observation)
        return queryObserved
    }

    private func selectSpotlightKeyboard(for query: String, checkpoint: String, waitDeadline: Date? = nil) throws {
        // Typing Cyrillic through XCTest does not change the keyboard's input language.
        // Use the observed globe control, then verify the actual alphabet before typing.
        let russian = query.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
        let expectedKeys = russian ? ["й", "ц", "у"] : ["q", "w", "e"]
        let keyboard = spotlight.keyboards.firstMatch
        attachSpotlightHierarchy("\(checkpoint)-keyboard-before")
        guard keyboard.waitForExistence(timeout: min(timeout, max(0, waitDeadline?.timeIntervalSinceNow ?? timeout))) else {
            throw DiscoveryFailure.missingSpotlightKeyboard(query)
        }
        let tutorial = spotlight.staticTexts["Quickly Change Keyboards"].firstMatch
        let keyboardDeadline = min(Date().addingTimeInterval(timeout), waitDeadline ?? .distantFuture)
        var dismissedTutorial = false
        var keyboardSwitches = 0
        var layoutBeforeSwitch: [String]?
        var observedLayout = keyboard.keys.allElementsBoundByIndex.map(\.label)
        var layoutChangedAt = Date()
        while true {
            // The first-use overlay can arrive after the initial keyboard snapshot.
            if tutorial.exists {
                guard !dismissedTutorial else { throw DiscoveryFailure.keyboardTutorialNotDismissed }
                attach("\(checkpoint)-keyboard-tutorial")
                attachSpotlightHierarchy("\(checkpoint)-keyboard-tutorial")
                let continueButton = spotlight.buttons["Continue"].firstMatch
                guard continueButton.waitForExistence(timeout: max(0, keyboardDeadline.timeIntervalSinceNow)),
                    continueButton.isHittable
                else {
                    throw DiscoveryFailure.missingKeyboardTutorialContinue
                }
                continueButton.tap()
                dismissedTutorial = true
                let dismissed = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: tutorial
                )
                guard XCTWaiter.wait(for: [dismissed], timeout: max(0, keyboardDeadline.timeIntervalSinceNow)) == .completed else {
                    throw DiscoveryFailure.keyboardTutorialNotDismissed
                }
                attach("\(checkpoint)-keyboard-tutorial-dismissed")
                attachSpotlightHierarchy("\(checkpoint)-keyboard-tutorial-dismissed")
            }
            if expectedKeys.allSatisfy({ keyboard.keys[$0].exists && keyboard.keys[$0].isHittable }), !tutorial.exists {
                break
            }
            guard Date() < keyboardDeadline else {
                attachSpotlightHierarchy("\(checkpoint)-keyboard-mismatch")
                throw DiscoveryFailure.mismatchedSpotlightKeyboard(query)
            }
            let layout = keyboard.keys.allElementsBoundByIndex.map(\.label)
            if layout != observedLayout {
                observedLayout = layout
                layoutChangedAt = Date()
            }
            // Extra installed keyboards can make one globe tap land on another alphabet.
            // Require a changed, settled layout before another tap so transitions cannot skip the target.
            let switchSettled =
                layoutBeforeSwitch == nil
                || (layout != layoutBeforeSwitch && Date().timeIntervalSince(layoutChangedAt) >= 0.75)
            if !expectedKeys.allSatisfy({ keyboard.keys[$0].exists }), !tutorial.exists, switchSettled {
                guard keyboardSwitches < 4 else {
                    attachSpotlightHierarchy("\(checkpoint)-keyboard-mismatch")
                    throw DiscoveryFailure.mismatchedSpotlightKeyboard(query)
                }
                let nextKeyboard = spotlight.buttons["Next keyboard"].firstMatch
                guard nextKeyboard.waitForExistence(timeout: max(0, keyboardDeadline.timeIntervalSinceNow)),
                    nextKeyboard.isHittable
                else {
                    throw DiscoveryFailure.missingSpotlightKeyboardControl
                }
                layoutBeforeSwitch = layout
                nextKeyboard.tap()
                keyboardSwitches += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        let search = spotlight.textFields["SpotlightSearchField"].firstMatch
        guard search.exists, search.isHittable else {
            throw DiscoveryFailure.missingSpotlightSearchField(query)
        }
        search.tap()
        // The observed native snapshot exposes this focus marker without private focus APIs.
        let focusDeadline = min(Date().addingTimeInterval(timeout), waitDeadline ?? .distantFuture)
        while !search.debugDescription.contains("Keyboard Focused") {
            guard Date() < focusDeadline else {
                throw DiscoveryFailure.spotlightSearchNotFocused(query)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        attachSpotlightHierarchy("\(checkpoint)-keyboard-ready")
    }

    private func clearSpotlightQuery(_ search: XCUIElement, waitDeadline: Date? = nil) throws {
        search.tap()
        let placeholder = search.placeholderValue
        if let existing = search.value as? String, !existing.isEmpty, existing != placeholder {
            // Spotlight restores the previous query with an arbitrary cursor position.
            // Its observed native clear button removes the complete query in one action.
            let clear = search.buttons["Clear text"].firstMatch
            guard clear.waitForExistence(timeout: min(timeout, max(0, waitDeadline?.timeIntervalSinceNow ?? timeout))),
                clear.isHittable
            else {
                throw DiscoveryFailure.missingSpotlightClearControl
            }
            clear.tap()
        }
        let empty = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == nil OR value == '' OR value == %@", placeholder ?? ""),
            object: search
        )
        guard XCTWaiter.wait(for: [empty], timeout: min(timeout, max(0, waitDeadline?.timeIntervalSinceNow ?? timeout))) == .completed else {
            throw DiscoveryFailure.spotlightQueryNotCleared(String(describing: search.value))
        }
        search.tap()
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
        case missingSpotlightResultsCollection
        case missingSpotlightKeyboard(String)
        case missingSpotlightKeyboardControl
        case mismatchedSpotlightKeyboard(String)
        case missingKeyboardTutorialContinue
        case keyboardTutorialNotDismissed
        case spotlightSearchNotFocused(String)
        case missingSpotlightClearControl
        case spotlightQueryNotCleared(String)
        case mismatchedDiagnosticQuery(String, String)
        case diagnosticWaitBudgetExpired
        case diagnosticPriorResultNotCleared
        case missingSpotlightResult(String, String)
    }
}
