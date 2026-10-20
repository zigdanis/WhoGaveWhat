import XCTest

final class AdaptiveGiftJourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 12
    private let photoLoadTimeout: TimeInterval = 60
    // "flowers" matches the keyword fallback, so the quick gift gets 💐 without a model.
    private var quickGiftName = "CI flowers \(UUID().uuidString.prefix(8))"
    private var detailedGiftName = "CI detailed gift \(UUID().uuidString.prefix(8))"
    private var giverName = "CI giver \(UUID().uuidString.prefix(8))"
    private var recipientName = "CI recipient \(UUID().uuidString.prefix(8))"
    private var friendName = "CI friend \(UUID().uuidString.prefix(8))"
    private var occasionName = "CI housewarming \(UUID().uuidString.prefix(8))"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["KS_START"] = "app"
        // The store survives between tests; never inherit a viewpoint from an earlier journey.
        app.launchEnvironment["KS_RESET_SELF"] = "1"
        app.launchEnvironment["KS_CLOUD_ICONS"] = "stub"
        app.launchEnvironment["KS_CLOUD_ICON_CONSENT"] = "declined"
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

    /// The core flow, once and in one launch: a quick gift, a detailed gift, a person's
    /// lifecycle and Insights. Checks for a specific feature belong in a temporary test.
    func testAdaptiveGiftJourney() throws {
        attach("home-start")
        addQuickGift()
        try addDetailedGift()
        try addEditAndDeletePerson()
        verifyInsights()
    }

    /// Name, giver and recipient only; the icon comes from the name.
    private func addQuickGift() {
        typeGiftName(quickGiftName)
        waitForValue(app.buttons["add-gift.emoji"], expected: "💐")
        choosePerson(giverName, endpoint: "from", create: true)
        choosePerson(recipientName, endpoint: "to", create: true)
        attach("quick-gift")
        saveGift(named: quickGiftName)
        attach("quick-gift-saved")
    }

    /// Every detail: a custom icon, an existing giver, a recipient created on the way,
    /// a value, a calendar date and a new occasion.
    private func addDetailedGift() throws {
        typeGiftName(detailedGiftName)
        app.buttons["add-gift.emoji"].tap()
        let icon = app.textFields["add-gift.icon.custom"]
        XCTAssertTrue(icon.waitForExistence(timeout: timeout))
        icon.tap()
        waitForKeyboardFocus(icon)
        icon.typeText("J")
        app.buttons["add-gift.icon.add"].tap()
        waitForValue(app.buttons["add-gift.emoji"], expected: "J")

        choosePerson(giverName, endpoint: "from", create: false)
        choosePerson(friendName, endpoint: "to", create: true)

        let details = app.buttons["add-gift.details"]
        details.tap()
        waitForValue(details, expected: "Shown")
        let value = app.textFields["add-gift.value"]
        value.tap()
        waitForKeyboardFocus(value)
        value.typeText("42")
        XCTAssertEqual(value.value as? String, "42")

        try pickCalendarDate()

        app.buttons["add-gift.occasion"].tap()
        let occasion = app.textFields["add-gift.occasion.custom"]
        XCTAssertTrue(occasion.waitForExistence(timeout: timeout))
        occasion.tap()
        waitForKeyboardFocus(occasion)
        occasion.typeText(occasionName)
        app.buttons["add-gift.occasion.add"].tap()
        waitForValue(app.buttons["add-gift.occasion"], expected: occasionName)

        attach("detailed-gift")
        saveGift(named: detailedGiftName)
        attach("detailed-gift-saved")
    }

    /// Picks a past day that is neither Today nor Yesterday and stays in this year,
    /// which Home and Insights show: the 15th of last month, or early January.
    private func pickCalendarDate() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        let target: Date
        if month > 1 {
            let lastMonth = try XCTUnwrap(calendar.date(byAdding: .month, value: -1, to: today))
            var components = calendar.dateComponents([.year, .month], from: lastMonth)
            components.day = 15
            target = try XCTUnwrap(calendar.date(from: components))
        } else {
            // Only January 1 and 2 have no such day; a later January day is the fallback.
            var components = calendar.dateComponents([.year, .month], from: today)
            components.day = day > 2 ? 1 : 10
            target = try XCTUnwrap(calendar.date(from: components))
        }

        app.buttons["add-gift.date"].tap()
        let picker = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'date-picker.calendar.selected-'")
        ).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        let shownMonth = try monthHeading(in: picker)
        if month > 1 {
            let previous = picker.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'previous'")).firstMatch
            if previous.exists && previous.isHittable { previous.tap() } else { picker.swipeRight() }
            _ = try monthHeading(in: picker, excluding: shownMonth)
        }
        // The calendar keeps neighbouring months loaded; tap the day on the visible page.
        let targetDay = calendar.component(.day, from: target)
        let days = picker.descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES %@", "^(.*[^0-9])?\(targetDay)([^0-9].*)?$")
        )
        var dayCell: XCUIElement?
        _ = waitWithOneRetry(timeout: timeout) {
            dayCell = days.allElementsBoundByIndex.first { $0.isHittable && picker.frame.contains($0.frame) }
            return dayCell != nil
        }
        attach("calendar")
        try XCTUnwrap(dayCell, picker.debugDescription).tap()
        let label = target.formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US")))
        waitForValue(app.buttons["add-gift.date"], expected: label)
    }

    /// Creates a person in People, renames them and sets a photo, then deletes them.
    private func addEditAndDeletePerson() throws {
        let personName = "CI person \(UUID().uuidString.prefix(8))"
        app.tabBars.buttons["People"].tap()
        let addPerson = app.buttons["people.add-person"]
        XCTAssertTrue(addPerson.waitForExistence(timeout: timeout))
        addPerson.tap()
        let nameField = app.textFields["person-editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(personName)
        app.buttons["person-editor.save"].tap()
        let row = app.staticTexts[personName]
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        attach("person-created")

        row.tap()
        XCTAssertTrue(app.navigationBars[personName].waitForExistence(timeout: timeout))
        app.buttons["person-detail.edit"].tap()
        let editorName = app.textFields["person-editor.name"]
        XCTAssertTrue(editorName.waitForExistence(timeout: timeout))
        editorName.tap()
        waitForKeyboardFocus(editorName)
        editorName.typeText(" edited")
        let editedName = try XCTUnwrap(editorName.value as? String)
        XCTAssertTrue(editedName.contains("edited"))
        editorName.typeText("\n")
        waitForDisappearance(app.keyboards.firstMatch)
        choosePersonPhoto()
        attach("person-editor-photo")
        app.buttons["person-editor.save"].tap()

        let detail = app.navigationBars[editedName]
        XCTAssertTrue(detail.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.images["person-detail.hero"].waitForExistence(timeout: timeout))
        attach("person-edited")

        // iOS 26 nests the toolbar button in a wrapper with the same identifier; tap the wrapper.
        let edit = detail.otherElements["person-detail.edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitWithOneRetry(timeout: timeout) { edit.isHittable })
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let delete = app.buttons["person-editor.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: timeout))
        delete.tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: timeout))
        attach("person-delete-confirmation")
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: timeout))
        waitForDisappearance(app.staticTexts[editedName])
        attach("person-deleted")
    }

    /// One pick from the Photos library, confirmed at the crop step.
    private func choosePersonPhoto() {
        app.buttons["person-editor.photo"].tap()
        let choosePhoto = app.buttons["person-editor.choose-photo"]
        XCTAssertTrue(choosePhoto.waitForExistence(timeout: timeout))
        choosePhoto.tap()
        let picker = app.navigationBars["Photos"]
        XCTAssertTrue(picker.waitForExistence(timeout: photoLoadTimeout))
        let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH[c] 'Photo,'"))
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: photoLoadTimeout))
        // XCTest snapshots are slow on a cold Simulator; wait until the first tile stops moving.
        var previousFrame: CGRect?
        let settled = waitWithOneRetry(timeout: timeout, interval: 0.3) {
            let frame = photos.firstMatch.frame
            defer { previousFrame = frame }
            return !frame.isEmpty && app.windows.firstMatch.frame.contains(frame) && frame == previousFrame
        }
        XCTAssertTrue(settled, "The first photo tile did not settle within \(timeout * 2)s")
        attach("person-photo-picker")
        // Visible Photos tiles may be reported as non-hittable; tap the tile's own center.
        photos.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let cropConfirm = app.buttons["crop.use"]
        XCTAssertTrue(waitForCrop(cropConfirm, picker: picker, photos: photos))
        waitForDisappearance(picker)
        attach("person-photo-crop")
        cropConfirm.tap()
        XCTAssertTrue(app.staticTexts["person-editor.title"].waitForExistence(timeout: timeout))
    }

    /// The giver's balances and a giver-friend comparison, before and after the giver becomes "You".
    private func verifyInsights() {
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: timeout))
        let subject = app.buttons["insights.balances.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: timeout))
        subject.tap()
        pickInsightsPerson(giverName)
        XCTAssertTrue(balanceRow(recipientName).waitForExistence(timeout: timeout))
        XCTAssertTrue(balanceRow(friendName).waitForExistence(timeout: timeout))
        XCTAssertTrue(balanceRow(friendName).label.contains("42"), balanceRow(friendName).label)
        attach("insights-balances")

        app.swipeUp()
        let personA = app.buttons["insights.compare.a"]
        XCTAssertTrue(personA.waitForExistence(timeout: timeout))
        personA.tap()
        pickInsightsPerson(giverName)
        app.buttons["insights.compare.b"].tap()
        pickInsightsPerson(friendName)
        let flow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "\(giverName) → \(friendName)")).firstMatch
        XCTAssertTrue(flow.waitForExistence(timeout: timeout))
        XCTAssertTrue(flow.label.contains("42"), flow.label)
        attach("insights-compare")

        selectTab("People")
        let giverRow = app.staticTexts[giverName]
        XCTAssertTrue(giverRow.waitForExistence(timeout: timeout))
        giverRow.tap()
        let meSwitch = app.switches["person-detail.is-me"]
        XCTAssertTrue(meSwitch.waitForExistence(timeout: timeout))
        // The switch sits at the trailing edge; the label area of a row toggle is not tappable.
        meSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.5)).tap()
        waitForValue(meSwitch, expected: "1")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Insights"].tap()
        waitForDisappearance(subject)
        XCTAssertTrue(balanceRow(friendName).waitForExistence(timeout: timeout))
        XCTAssertTrue(personA.label.contains(giverName), personA.label)
        XCTAssertTrue(flow.waitForExistence(timeout: timeout))
        attach("insights-me")
    }

    /// While scrolled down, the tab bar collapses to the current tab; scroll back up to expand it.
    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        for _ in 0..<3 where !tab.waitForExistence(timeout: 2) {
            app.swipeDown()
        }
        tab.tap()
    }

    private func typeGiftName(_ name: String) {
        app.tabBars.buttons["Home"].tap()
        app.buttons["Add a gift"].tap()
        let field = app.textFields["add-gift.name"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        waitForKeyboardFocus(field)
        field.typeText(name)
    }

    private func choosePerson(_ name: String, endpoint: String, create: Bool) {
        app.buttons["add-gift.\(endpoint)"].tap()
        let query = app.textFields["person-picker.query"]
        XCTAssertTrue(query.waitForExistence(timeout: timeout))
        if create {
            query.tap()
            query.typeText(name)
            app.buttons["person-picker.add"].tap()
        } else {
            let rows = personRows(named: name)
            XCTAssertEqual(rows.count, 1)
            rows.first?.tap()
        }
        waitForDisappearance(query)
        waitForValue(app.buttons["add-gift.\(endpoint)"], expected: name)
    }

    private func saveGift(named name: String) {
        let save = app.buttons["add-gift.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        waitForDisappearance(save)
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: timeout))
    }

    private func pickInsightsPerson(_ name: String) {
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'insights.picker.person.' AND label CONTAINS %@", name)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        waitForDisappearance(row)
    }

    private func balanceRow(_ name: String) -> XCUIElement {
        element(identifier: "insights.balances").buttons
            .matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    func testAddGiftSheetSizesCompactAndExpandedContent() throws {
        app.buttons["Add a gift"].tap()

        let giftTitle = app.descendants(matching: .any)["add-gift.title"]
        XCTAssertTrue(giftTitle.waitForExistence(timeout: timeout))
        XCTAssertLessThanOrEqual(
            abs(giftTitle.frame.midX - app.windows.firstMatch.frame.midX),
            2,
            "Compact gift sheet title should remain centered"
        )
        let giftNameField = app.textFields["add-gift.name"]
        XCTAssertTrue(giftNameField.waitForExistence(timeout: timeout))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        let save = app.buttons["add-gift.save"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        assertCompactSaveGap(save, keyboard: keyboard)
        attach("gift-content-sized-compact-keyboard")

        app.buttons["add-gift.details"].tap()
        XCTAssertTrue(app.textFields["add-gift.value"].waitForExistence(timeout: timeout))
        XCTAssertTrue(keyboard.exists, "Expanding Details should preserve name-field autofocus")
        assertExpandedSheetUsesAvailableHeight()

        app.buttons["add-gift.details"].tap()
        waitForDisappearance(keyboard)
        app.buttons["add-gift.details"].tap()
        XCTAssertTrue(app.textFields["add-gift.value"].waitForExistence(timeout: timeout))
        assertDetailsContentFits(save)
        attach("gift-content-sized-details")

        let value = app.textFields["add-gift.value"]
        value.tap()
        waitForKeyboardFocus(value)
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        value.typeText("42")
        assertExpandedSheetUsesAvailableHeight()
        assertSaveReachableAboveKeyboard(save, keyboard: keyboard)
        attach("gift-content-sized-details-keyboard")

        app.buttons["add-gift.details"].tap()
        waitForDisappearance(keyboard)
        XCTAssertEqual(app.buttons["add-gift.details"].value as? String, "Hidden")
        giftNameField.tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        assertCompactSaveGap(save, keyboard: keyboard)
        attach("gift-content-sized-refocused-compact-keyboard")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: timeout))
    }

    func testCloudIconConsentAndSettings() {
        verifyCloudIconConsentAndSettings(appearance: "light", checkpointPrefix: "")
        verifyCloudIconConsentAndSettings(appearance: "dark", checkpointPrefix: "dark-")
    }

    private func verifyCloudIconConsentAndSettings(appearance: String, checkpointPrefix: String) {
        app.terminate()
        app.launchEnvironment["KS_APPEARANCE"] = appearance
        app.launchEnvironment["KS_CLOUD_ICON_CONSENT"] = "undecided"
        app.launch()
        XCTAssertTrue(element(identifier: "appearance.\(appearance)").waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["Add a gift"].waitForExistence(timeout: timeout))
        app.buttons["Add a gift"].tap()

        let name = app.textFields["add-gift.name"]
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        waitForKeyboardFocus(name)
        name.typeText("гитара")

        let allow = app.buttons["add-gift.cloud-icons.allow"]
        XCTAssertTrue(element(identifier: "add-gift.cloud-icons.consent").waitForExistence(timeout: timeout))
        XCTAssertTrue(allow.waitForExistence(timeout: timeout))
        let scroll = app.scrollViews["add-gift.scroll"]
        for _ in 0..<4 where !allow.isHittable {
            if !scrollUpWithinVisibleArea(scroll, aboveKeyboard: app.keyboards.firstMatch) { break }
        }
        XCTAssertTrue(allow.isHittable)
        attach("\(checkpointPrefix)cloud-icons-consent")
        allow.tap()
        waitForDisappearance(allow)
        waitForDisappearance(app.keyboards.firstMatch)

        let emoji = app.buttons["add-gift.emoji"]
        waitForValue(emoji, expected: "🎸")
        XCTAssertEqual(name.value as? String, "гитара")
        attach("\(checkpointPrefix)cloud-icons-suggestion")

        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: timeout))
        app.buttons["Settings"].tap()
        let toggle = app.switches["settings.cloud-icons"]
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout))
        waitForValue(toggle, expected: "1")
        XCTAssertTrue(element(identifier: "settings.privacy-policy").exists)
        attach("\(checkpointPrefix)cloud-icons-settings")
        // Tap the switch itself; the row's center is its label.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.5)).tap()
        waitForValue(toggle, expected: "0")
        app.buttons["Done"].tap()

        // Declining in Settings suppresses future in-sheet prompts.
        app.buttons["Add a gift"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        waitForKeyboardFocus(name)
        name.typeText("гитара")
        XCTAssertFalse(allow.waitForExistence(timeout: 1))
        app.buttons["Cancel"].tap()
    }

    func testAddPersonCreateCancelAndDeleteConfirmation() throws {
        let people = app.tabBars.buttons["People"]
        XCTAssertTrue(people.waitForExistence(timeout: timeout))
        people.tap()

        let cancelledName = "CI cancelled person \(UUID().uuidString.prefix(8))"
        let personName = "CI disposable person \(UUID().uuidString.prefix(8))"
        let addPerson = app.buttons["people.add-person"]
        XCTAssertTrue(addPerson.waitForExistence(timeout: timeout))

        addPerson.tap()
        let cancelledNameField = app.textFields["person-editor.name"]
        XCTAssertTrue(cancelledNameField.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.textFields["add-gift.name"].exists)
        cancelledNameField.tap()
        cancelledNameField.typeText(cancelledName)
        attach("person-add-cancel-draft")
        app.buttons["person-editor.cancel"].tap()
        XCTAssertFalse(app.staticTexts[cancelledName].waitForExistence(timeout: 1))

        XCTAssertTrue(addPerson.waitForExistence(timeout: timeout))
        addPerson.tap()
        let nameField = app.textFields["person-editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(personName)
        let save = app.buttons["person-editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        XCTAssertTrue(save.isEnabled)
        assertPersonEditorControlsFitAboveKeyboard([nameField, save], keyboard: app.keyboards.firstMatch)
        save.tap()

        let personRow = app.staticTexts[personName]
        XCTAssertTrue(personRow.waitForExistence(timeout: timeout))
        attach("person-add-created")
        personRow.tap()
        XCTAssertTrue(app.navigationBars[personName].waitForExistence(timeout: timeout))
        app.buttons["person-detail.edit"].tap()

        let editorTitle = app.staticTexts["person-editor.title"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        XCTAssertEqual(editorTitle.label, personName)
        let editorName = app.textFields["person-editor.name"]
        XCTAssertTrue(editorName.waitForExistence(timeout: timeout))
        let editorKeyboard = app.keyboards.firstMatch
        XCTAssertFalse(editorKeyboard.exists, "Editing a person should open without the keyboard")
        attach("person-editor")
        editorName.tap()
        XCTAssertTrue(editorKeyboard.waitForExistence(timeout: timeout))
        attach("person-editor-keyboard")
        editorName.typeText(" draft")
        let editedName = try XCTUnwrap(editorName.value as? String)
        XCTAssertNotEqual(editedName, personName)
        XCTAssertTrue(editedName.contains("draft"))
        attach("person-editor-delete-keyboard")

        let delete = app.buttons["person-editor.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: timeout))
        let choosePhoto = app.buttons["person-editor.photo"]
        assertPersonEditorControlsFitAboveKeyboard([editorName, choosePhoto, delete], keyboard: editorKeyboard)
        delete.tap()

        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: timeout))
        XCTAssertTrue(confirmation.staticTexts["Delete \(personName)?"].exists)
        XCTAssertTrue(
            confirmation.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'all 0 of their gifts'")).firstMatch.exists
        )
        attach("person-editor-delete-confirmation")
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        XCTAssertEqual(editorName.value as? String, editedName)
        attach("person-editor-delete-cancelled")

        app.buttons["person-editor.save"].tap()
        XCTAssertTrue(app.navigationBars[editedName].waitForExistence(timeout: timeout))
        app.buttons["person-detail.edit"].tap()
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        let persistedName = app.textFields["person-editor.name"]
        XCTAssertTrue(persistedName.waitForExistence(timeout: timeout))
        XCTAssertEqual(persistedName.value as? String, editedName)
        XCTAssertFalse(editorKeyboard.exists)
        let persistedDelete = app.buttons["person-editor.delete"]
        XCTAssertTrue(persistedDelete.waitForExistence(timeout: timeout))
        persistedDelete.tap()

        XCTAssertTrue(confirmation.waitForExistence(timeout: timeout))
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts[editedName].exists)
        attach("person-add-deleted")
    }

    func testMarkingPersonAsMeShowsYouBadgeAndDeletingClearsIt() throws {
        let personName = "CI me person \(UUID().uuidString.prefix(8))"
        let prompt = app.buttons["year-summary.mark-self"]
        let badge = app.staticTexts["people.you-badge"]

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: timeout))

        app.tabBars.buttons["People"].tap()
        let addPerson = app.buttons["people.add-person"]
        XCTAssertTrue(addPerson.waitForExistence(timeout: timeout))
        addPerson.tap()
        let nameField = app.textFields["person-editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(personName)
        app.buttons["person-editor.save"].tap()

        let personRow = app.staticTexts[personName]
        XCTAssertTrue(personRow.waitForExistence(timeout: timeout))
        XCTAssertFalse(badge.exists)
        personRow.tap()
        XCTAssertTrue(app.navigationBars[personName].waitForExistence(timeout: timeout))
        let meSwitch = app.switches["person-detail.is-me"]
        XCTAssertTrue(meSwitch.waitForExistence(timeout: timeout))
        XCTAssertEqual(meSwitch.value as? String, "0")
        // The switch sits at the trailing edge; the label area of a row toggle is not tappable.
        meSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: meSwitch)
        waitForExpectations(timeout: timeout)
        attach("person-detail-is-me")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(badge.waitForExistence(timeout: timeout))
        attach("people-you-badge")

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: timeout))
        XCTAssertFalse(prompt.exists)

        app.tabBars.buttons["People"].tap()
        XCTAssertTrue(personRow.waitForExistence(timeout: timeout))
        personRow.tap()
        app.buttons["person-detail.edit"].tap()
        let delete = app.buttons["person-editor.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: timeout))
        delete.tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: timeout))
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: timeout))
        XCTAssertFalse(badge.exists)

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: timeout))
    }

    func testPersonEditorTitleUsesRussianLocalization() throws {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        let people = app.tabBars.buttons["Люди"]
        XCTAssertTrue(people.waitForExistence(timeout: timeout))
        people.tap()
        app.buttons["people.add-person"].tap()
        let personName = "CI localized person \(UUID().uuidString.prefix(8))"
        let nameField = app.textFields["person-editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.typeText(personName)
        app.buttons["person-editor.save"].tap()

        let personRow = app.staticTexts[personName]
        XCTAssertTrue(personRow.waitForExistence(timeout: timeout))
        personRow.tap()
        app.buttons["person-detail.edit"].tap()
        let editorTitle = app.staticTexts["person-editor.title"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        XCTAssertEqual(editorTitle.label, personName)
        let keyboard = app.keyboards.firstMatch
        XCTAssertFalse(keyboard.exists)
        XCTAssertEqual(app.buttons["person-editor.cancel"].label, "Отмена")
        XCTAssertEqual(app.buttons["person-editor.save"].label, "Сохранить")
        let delete = app.buttons["person-editor.delete"]
        XCTAssertEqual(delete.label, "Удалить")
        XCTAssertEqual(app.buttons["person-editor.photo"].label, "Выбрать фото")
        attach("person-editor-russian")
        app.textFields["person-editor.name"].tap()
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        attach("person-editor-russian-keyboard")
        app.buttons["person-editor.cancel"].tap()
    }

    func testPersonEditorHeaderAdaptsToAccessibilityDynamicType() throws {
        let personName = "CI large type person \(UUID().uuidString.prefix(8))"
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.launch()

        let people = app.tabBars.buttons["Люди"]
        XCTAssertTrue(people.waitForExistence(timeout: timeout))
        people.tap()
        app.buttons["people.add-person"].tap()
        let newName = app.textFields["person-editor.name"]
        XCTAssertTrue(newName.waitForExistence(timeout: timeout))
        newName.typeText(personName)
        app.buttons["person-editor.save"].tap()

        let personRow = app.staticTexts[personName]
        XCTAssertTrue(personRow.waitForExistence(timeout: timeout))
        personRow.tap()
        app.buttons["person-detail.edit"].tap()

        let title = app.staticTexts["person-editor.title"]
        let cancel = app.buttons["person-editor.cancel"]
        let save = app.buttons["person-editor.save"]
        XCTAssertTrue(title.waitForExistence(timeout: timeout))
        XCTAssertTrue(cancel.waitForExistence(timeout: timeout))
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(title.label, personName)
        let normalTitleHeight = title.frame.height
        app.buttons["person-editor.cancel"].tap()

        app.terminate()
        app.launchArguments = [
            "-AppleLanguages", "(ru)",
            "-AppleLocale", "ru_RU",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        XCTAssertTrue(people.waitForExistence(timeout: timeout))
        people.tap()
        // Names wrap at accessibility sizes, so the row can start below the fold.
        for _ in 0..<8 where !personRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(personRow.waitForExistence(timeout: timeout))
        personRow.tap()
        app.buttons["person-detail.edit"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(title.label, personName)
        XCTAssertGreaterThan(title.frame.height, normalTitleHeight)
        XCTAssertFalse(title.frame.intersects(cancel.frame), "Localized title must not overlap Cancel")
        XCTAssertFalse(title.frame.intersects(save.frame), "Localized title must not overlap Save")

        let delete = app.buttons["person-editor.delete"]
        let photo = app.buttons["person-editor.photo"]
        let name = app.textFields["person-editor.name"]
        let scroll = app.scrollViews["person-editor.scroll"]
        XCTAssertTrue(delete.waitForExistence(timeout: timeout))
        XCTAssertTrue(photo.waitForExistence(timeout: timeout))
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        let grabber = frontmostSheetGrabber()
        for headerElement in [title, cancel, save] {
            XCTAssertGreaterThanOrEqual(
                headerElement.frame.minY,
                grabber.frame.minY,
                "Header content must begin below the sheet grabber: \(headerElement)"
            )
        }
        let headerBottom = max(max(title.frame.maxY, cancel.frame.maxY), save.frame.maxY)
        XCTAssertLessThanOrEqual(
            headerBottom,
            name.frame.minY,
            "The complete editor header must end before the first editor field"
        )
        XCTAssertLessThanOrEqual(
            headerBottom,
            photo.frame.minY,
            "The complete editor header must end before the Photo control"
        )
        XCTAssertLessThanOrEqual(
            headerBottom,
            scroll.frame.minY,
            "Header and scrollable editor content must not overlap"
        )
        XCTAssertLessThanOrEqual(headerBottom, scroll.frame.minY, "Header must stay above the scroll viewport")
        XCTAssertTrue(title.isHittable, "The title must stay fully visible after scrolling")
        XCTAssertTrue(cancel.isHittable, "Cancel must stay reachable after scrolling")
        XCTAssertTrue(save.isHittable, "Save must stay reachable after scrolling")
        attach("person-editor-header-accessibility")
        name.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        for _ in 0..<5 where !delete.isHittable {
            guard scrollUpWithinVisibleArea(scroll, aboveKeyboard: keyboard) else { break }
        }
        XCTAssertTrue(delete.isHittable, "Delete must remain reachable in the large-type editor")
        XCTAssertLessThanOrEqual(delete.frame.maxY, visibleKeyboardTop(keyboard))
        attach("person-editor-header-accessibility-keyboard")
        app.buttons["person-editor.cancel"].tap()
    }

    /// Home summary without a viewpoint, then Insights balances and comparison once the giver is "You".
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertCompactSaveGap(_ save: XCUIElement, keyboard: XCUIElement) {
        let grabber = frontmostSheetGrabber()
        let window = app.windows.firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))

        var previousMeasurement: (gap: CGFloat, sheetHeight: CGFloat)?
        var stableSamples = 0
        var gap: CGFloat = 0
        var sheetHeight: CGFloat = 0
        _ = waitWithOneRetry(timeout: timeout, interval: 0.1) {
            let keyboardTop = visibleKeyboardTop(keyboard)
            gap = keyboardTop - save.frame.maxY
            sheetHeight = keyboardTop - grabber.frame.minY
            if let previousMeasurement,
                abs(gap - previousMeasurement.gap) <= 2,
                abs(sheetHeight - previousMeasurement.sheetHeight) <= 2
            {
                stableSamples += 1
            } else {
                stableSamples = 0
            }
            previousMeasurement = (gap, sheetHeight)
            return stableSamples >= 2
        }
        XCTAssertGreaterThanOrEqual(stableSamples, 2, "Compact sheet geometry did not settle")
        XCTAssertGreaterThanOrEqual(gap, 0, "Save must remain above the keyboard: save=\(save.frame), keyboard=\(keyboard.frame)")
        XCTAssertLessThanOrEqual(gap, 48, "Compact Save-to-keyboard gap should stay within 48 pt: gap=\(gap)")

        XCTAssertLessThanOrEqual(sheetHeight, 520, "The keyboard-open compact sheet should size to its content: height=\(sheetHeight)")
    }

    private func assertDetailsContentFits(_ save: XCUIElement) {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var previousBottomGap: CGFloat?
        var bottomGap: CGFloat = 0
        var stableSamples = 0
        while Date() < deadline {
            bottomGap = window.frame.maxY - save.frame.maxY
            if save.isHittable, let previousBottomGap, abs(bottomGap - previousBottomGap) <= 2 {
                stableSamples += 1
            } else {
                stableSamples = 0
            }
            previousBottomGap = bottomGap
            if stableSamples >= 2 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertGreaterThanOrEqual(stableSamples, 2, "Save did not settle into the expanded Details sheet")
        XCTAssertLessThanOrEqual(
            bottomGap,
            110,
            "Expanded Details should end near Save when its content fits: gap=\(bottomGap)"
        )
    }

    private func assertExpandedSheetUsesAvailableHeight() {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        var top = CGFloat.greatestFiniteMagnitude
        var stableSamples = 0
        while Date() < deadline && stableSamples < 2 {
            let grabber = frontmostSheetGrabber()
            top = grabber.frame.minY
            if top <= window.frame.minY + 100 {
                stableSamples += 1
            } else {
                stableSamples = 0
            }
            if stableSamples < 2 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        }
        XCTAssertLessThanOrEqual(
            top,
            window.frame.minY + 100,
            "Expanded Details with the keyboard should use the available safe height: grabberTop=\(top), window=\(window.frame)"
        )
    }

    private func frontmostSheetGrabber() -> XCUIElement {
        let grabbers = sheetGrabbers()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let visible = grabbers.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            if let grabber = visible.max(by: { $0.frame.minY < $1.frame.minY }) {
                return grabber
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("No visible sheet grabber: \(grabbers.debugDescription)")
        return grabbers.firstMatch
    }

    private func sheetGrabbers() -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label == %@", "Sheet Grabber", "Точка захвата листа")
        )
    }

    private func assertSaveReachableAboveKeyboard(_ save: XCUIElement, keyboard: XCUIElement) {
        let scroll = app.scrollViews["add-gift.scroll"]
        for attempt in 0..<3 {
            if !keyboard.exists {
                XCTAssertTrue(save.isHittable)
                attach("details-value-keyboard-dismissed")
                return
            }
            let keyboardTop = visibleKeyboardTop(keyboard)
            if save.isHittable && save.frame.maxY <= keyboardTop {
                attach("details-value-keyboard")
                return
            }
            guard scrollUpWithinVisibleArea(scroll, aboveKeyboard: keyboard) else {
                XCTFail("No usable scroll area above keyboard: scroll=\(scroll.frame), visibleKeyboardTop=\(keyboardTop)")
                return
            }
            if attempt == 2 { break }
        }

        if !keyboard.exists {
            XCTAssertTrue(save.isHittable)
            attach("details-value-keyboard-dismissed")
        } else if save.isHittable && save.frame.maxY <= visibleKeyboardTop(keyboard) {
            attach("details-value-keyboard")
        } else {
            XCTFail("Save remains covered by keyboard: save=\(save.frame), visibleKeyboardTop=\(visibleKeyboardTop(keyboard))")
        }
    }

    private func assertPersonEditorControlsFitAboveKeyboard(_ controls: [XCUIElement], keyboard: XCUIElement) {
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: timeout))
            XCTAssertTrue(control.isHittable, "Editor control should be visible with the keyboard: \(control)")
            let keyboardTop = visibleKeyboardTop(keyboard)
            XCTAssertLessThanOrEqual(
                control.frame.maxY,
                keyboardTop,
                "Editor control should fit above the keyboard: control=\(control.frame), visibleKeyboardTop=\(keyboardTop)"
            )
        }
    }

    private func scrollUpWithinVisibleArea(_ scroll: XCUIElement, aboveKeyboard keyboard: XCUIElement) -> Bool {
        let window = app.windows.firstMatch
        let visibleBottom = min(visibleKeyboardTop(keyboard), window.frame.maxY) - 16
        let visibleFrame = scroll.frame.intersection(
            CGRect(
                x: scroll.frame.minX,
                y: scroll.frame.minY,
                width: scroll.frame.width,
                height: max(0, visibleBottom - scroll.frame.minY)
            )
        )
        guard visibleFrame.height > 40, visibleFrame.width > 40 else { return false }

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
        return true
    }

    private func keyboardIsVisible(_ keyboard: XCUIElement) -> Bool {
        guard keyboard.exists else { return false }
        let frame = keyboard.frame
        return frame.width > 0 && frame.height > 0 && frame.intersects(app.windows.firstMatch.frame)
    }

    private func visibleKeyboardTop(_ keyboard: XCUIElement) -> CGFloat {
        let windowFrame = app.windows.firstMatch.frame
        guard keyboardIsVisible(keyboard) else { return windowFrame.maxY }
        let keyboardFrame = keyboard.frame
        let assistantViews = app.descendants(matching: .any)
            .matching(identifier: "SystemInputAssistantView")
            .allElementsBoundByIndex

        let assistantTop =
            assistantViews
            .map(\.frame)
            .filter { frame in
                guard frame.width > 0, frame.height > 0, frame.intersects(windowFrame) else { return false }
                let horizontalOverlap = max(0, min(frame.maxX, keyboardFrame.maxX) - max(frame.minX, keyboardFrame.minX))
                return horizontalOverlap >= keyboardFrame.width * 0.8
                    && frame.minY < keyboardFrame.minY
                    && abs(frame.maxY - keyboardFrame.minY) <= 2
            }
            .map(\.minY)
            .min()

        return min(keyboardFrame.minY, assistantTop ?? keyboardFrame.minY)
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

    /// Waits for the photo crop screen; if the picker is still open, re-taps the first tile once.
    private func waitForCrop(_ cropConfirm: XCUIElement, picker: XCUIElement, photos: XCUIElementQuery) -> Bool {
        let recover = {
            let photo = photos.firstMatch
            guard picker.exists, !cropConfirm.exists, photo.exists else { return }
            photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        return waitWithOneRetry(timeout: photoLoadTimeout / 2, recover: recover) { cropConfirm.exists }
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

    private func waitForValue(_ element: XCUIElement, expected: String) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
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
}
