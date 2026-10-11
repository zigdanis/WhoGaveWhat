import XCTest

final class AdaptiveGiftJourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    private let timeout: TimeInterval = 12
    private let photoLoadTimeout: TimeInterval = 60
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
        assertCompactSaveGap(app.buttons["add-gift.save"], keyboard: app.keyboards.firstMatch)
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

        let details = app.buttons["add-gift.details"]
        details.tap()
        XCTAssertTrue(app.textFields["add-gift.value"].waitForExistence(timeout: timeout))
        XCTAssertEqual(details.value as? String, "Shown")
        let value = app.textFields["add-gift.value"]
        let save = app.buttons["add-gift.save"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        assertDetailsContentFits(save)
        value.tap()
        waitForKeyboardFocus(value)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout))
        value.typeText("42")
        XCTAssertEqual(value.value as? String, "42")
        let keyboard = app.keyboards.firstMatch
        assertSaveReachableAboveKeyboard(save, keyboard: keyboard)
        attach("details-value")

        app.buttons["add-gift.date"].tap()
        let calendar = app.otherElements.matching(
            NSPredicate(format: "identifier BEGINSWITH 'date-picker.calendar.selected-'")
        ).firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: timeout))
        let firstMonth = try monthHeading(in: calendar)
        let now = Date()
        let expectedMonth = DateFormatter()
        expectedMonth.locale = Locale(identifier: "en_US")
        expectedMonth.calendar = Calendar(identifier: .gregorian)
        expectedMonth.dateFormat = "MMMM yyyy"
        XCTAssertEqual(firstMonth, expectedMonth.string(from: now))
        XCTAssertTrue(app.buttons["date-picker.today"].exists)
        let dayComponents = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: now)
        let expectedDayIdentifier = String(
            format: "date-picker.calendar.selected-%04d-%02d-%02d",
            dayComponents.year ?? 0,
            dayComponents.month ?? 0,
            dayComponents.day ?? 0
        )
        XCTAssertEqual(calendar.identifier, expectedDayIdentifier)
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
        attach("people-populated")
        personRow.tap()
        let detailNavigationBar = app.navigationBars[giverName]
        XCTAssertTrue(detailNavigationBar.waitForExistence(timeout: timeout))
        let hero = app.images["person-detail.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: timeout))
        let displayedNames = app.staticTexts.matching(NSPredicate(format: "label == %@", giverName))
        XCTAssertEqual(displayedNames.count, 1)
        attach("person-detail")

        app.buttons["person-detail.edit"].tap()
        let editorTitle = app.staticTexts["person-editor.title"]
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        XCTAssertEqual(editorTitle.label, giverName)
        let editorName = app.textFields["person-editor.name"]
        XCTAssertTrue(editorName.waitForExistence(timeout: timeout))
        let editorKeyboard = app.keyboards.firstMatch
        XCTAssertFalse(editorKeyboard.exists, "Editing a person should open without the keyboard")
        let photoControl = app.buttons["person-editor.photo"]
        XCTAssertTrue(photoControl.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["person-editor.save"].isEnabled)
        attach("person-editor")
        let editorDelete = app.buttons["person-editor.delete"]
        XCTAssertTrue(editorDelete.waitForExistence(timeout: timeout))
        editorName.tap()
        XCTAssertTrue(editorKeyboard.waitForExistence(timeout: timeout))
        assertPersonEditorControlsFitAboveKeyboard([editorName, photoControl, editorDelete], keyboard: editorKeyboard)
        attach("person-editor-keyboard")
        editorName.typeText("\n")
        waitForDisappearance(editorKeyboard)
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))

        photoControl.tap()
        let choosePhoto = app.buttons["person-editor.choose-photo"]
        XCTAssertTrue(choosePhoto.waitForExistence(timeout: timeout))
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
        let cropConfirm = app.buttons["crop.use"]
        for attempt in 1...2 {
            guard pickerNavigationBar.exists, !cropConfirm.exists else { break }
            if attempt == 2, photoControl.exists,
                !photoControl.isEnabled || photoControl.images["hourglass"].exists
            {
                break
            }
            let frameDeadline = Date().addingTimeInterval(5)
            var previousFrame: CGRect?
            var settledPhoto: XCUIElement?
            while Date() < frameDeadline {
                guard pickerNavigationBar.exists, !cropConfirm.exists else { break }
                let candidate = photoImages.firstMatch
                if candidate.exists {
                    let frame = candidate.frame
                    let windowFrame = app.windows.firstMatch.frame
                    if frame.width > 0, frame.height > 0, windowFrame.contains(frame), frame == previousFrame {
                        settledPhoto = candidate
                        break
                    }
                    previousFrame = frame
                } else {
                    previousFrame = nil
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
            guard pickerNavigationBar.exists, !cropConfirm.exists else { break }
            let photo = try XCTUnwrap(settledPhoto, "The visible photo tile did not settle")
            let frame = photo.frame
            XCTAssertEqual(frame, previousFrame)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(frame))
            let target = XCTAttachment(
                string: "attempt=\(attempt)\nidentifier=\(photo.identifier)\nlabel=\(photo.label)\nframe=\(frame)\nhittable=\(photo.isHittable)"
            )
            target.name = "person-photo-selection-\(attempt)-target"
            target.lifetime = .keepAlways
            add(target)
            attach("person-photo-selection-\(attempt)-before")
            guard pickerNavigationBar.exists, !cropConfirm.exists else { break }
            if attempt == 2, photoControl.exists,
                !photoControl.isEnabled || photoControl.images["hourglass"].exists
            {
                break
            }
            XCTAssertTrue(photo.exists)
            XCTAssertEqual(photo.frame, frame)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(photo.frame))
            // Visible Photos tiles may be reported as non-hittable; target the tile's own center.
            photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let responseDeadline = Date().addingTimeInterval(5)
            while pickerNavigationBar.exists, !cropConfirm.exists, Date() < responseDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
            attach("person-photo-selection-\(attempt)-after")
            attachHierarchy("person-photo-selection-\(attempt)-after", selectedValue: nil)
        }
        waitForDisappearance(pickerNavigationBar)
        // Loading the selected asset can outlast a normal sheet transition on a cold Simulator.
        XCTAssertTrue(cropConfirm.waitForExistence(timeout: photoLoadTimeout))
        attach("person-photo-crop")
        app.buttons["crop.cancel"].tap()
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["person-editor.remove-photo"].exists)
        attach("person-editor-crop-cancelled")

        photoControl.tap()
        XCTAssertTrue(choosePhoto.waitForExistence(timeout: timeout))
        choosePhoto.tap()
        XCTAssertTrue(pickerNavigationBar.waitForExistence(timeout: 60))
        XCTAssertTrue(photoImages.firstMatch.waitForExistence(timeout: 60))
        let secondPhoto = photoImages.firstMatch
        let secondWindowFrame = app.windows.firstMatch.frame
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: secondPhoto.frame.midX / secondWindowFrame.width,
                dy: secondPhoto.frame.midY / secondWindowFrame.height
            )
        ).tap()
        XCTAssertTrue(cropConfirm.waitForExistence(timeout: photoLoadTimeout))
        let cropWindow = app.windows.firstMatch
        cropWindow.pinch(withScale: 1.35, velocity: 1)
        let cropStart = cropWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let cropEnd = cropWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.5))
        cropStart.press(forDuration: 0.1, thenDragTo: cropEnd)
        attach("person-photo-crop-adjusted")
        cropConfirm.tap()
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        attach("person-editor-photo")
        let removePhoto = app.buttons["person-editor.remove-photo"]
        photoControl.tap()
        XCTAssertTrue(removePhoto.waitForExistence(timeout: timeout))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        editorName.tap()
        XCTAssertTrue(editorKeyboard.waitForExistence(timeout: timeout))
        attach("person-editor-photo-keyboard")
        attach("person-editor-selected-photo")
        app.buttons["person-editor.save"].tap()
        waitForDisappearance(editorTitle)
        XCTAssertTrue(detailNavigationBar.waitForExistence(timeout: timeout))
        let detailReturnDeadline = Date().addingTimeInterval(timeout)
        while !detailNavigationBar.isHittable && Date() < detailReturnDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(detailNavigationBar.isHittable)
        XCTAssertTrue(hero.waitForExistence(timeout: timeout))
        attach("person-detail-selected-photo")

        // iOS 26 exposes a toolbar wrapper and nested button with the same identifier.
        // Resolve the current native wrapper and tap its observed center once.
        let editControl = detailNavigationBar.otherElements["person-detail.edit"].firstMatch
        XCTAssertTrue(editControl.waitForExistence(timeout: timeout))
        XCTAssertTrue(editControl.isHittable)
        let editFrame = editControl.frame
        XCTAssertFalse(editFrame.isEmpty)
        XCTAssertTrue(detailNavigationBar.frame.contains(editFrame))
        let target = XCTAttachment(
            string: "editFrame=\(editFrame)\ncenter=(\(editFrame.midX), \(editFrame.midY))\nbarFrame=\(detailNavigationBar.frame)"
        )
        target.name = "person-editor-reopen-target"
        target.lifetime = .keepAlways
        add(target)
        editControl.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        XCTAssertEqual(editorTitle.label, giverName)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        photoControl.tap()
        XCTAssertTrue(removePhoto.waitForExistence(timeout: timeout))
        attach("person-editor-photo-persisted")
        let changePhoto = app.buttons["person-editor.choose-photo"]
        XCTAssertTrue(changePhoto.waitForExistence(timeout: timeout))
        changePhoto.tap()
        XCTAssertTrue(pickerNavigationBar.waitForExistence(timeout: 60))
        XCTAssertTrue(photoImages.firstMatch.waitForExistence(timeout: 60))
        let replacementPhoto = photoImages.firstMatch
        let replacementWindow = app.windows.firstMatch.frame
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: replacementPhoto.frame.midX / replacementWindow.width,
                dy: replacementPhoto.frame.midY / replacementWindow.height
            )
        ).tap()
        XCTAssertTrue(cropConfirm.waitForExistence(timeout: photoLoadTimeout))
        attach("person-photo-replacement-crop")
        app.buttons["crop.cancel"].tap()
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        photoControl.tap()
        XCTAssertTrue(removePhoto.waitForExistence(timeout: timeout))
        attach("person-editor-existing-photo-crop-cancelled")
        removePhoto.tap()
        attach("person-editor-photo-removed")
        XCTAssertTrue(app.buttons["person-editor.save"].isEnabled)
        app.buttons["person-editor.save"].tap()
        XCTAssertTrue(detailNavigationBar.waitForExistence(timeout: timeout))
        app.buttons["person-detail.edit"].tap()
        XCTAssertTrue(editorTitle.waitForExistence(timeout: timeout))
        photoControl.tap()
        XCTAssertTrue(choosePhoto.waitForExistence(timeout: timeout))
        XCTAssertFalse(removePhoto.exists, "Removing and saving should persist the missing photo")
        attach("person-editor-photo-removal-persisted")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        app.buttons["person-editor.cancel"].tap()
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
        let grabbers = sheetGrabbers()
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

    private func assertCompactSaveGap(_ save: XCUIElement, keyboard: XCUIElement) {
        let grabber = frontmostSheetGrabber()
        let window = app.windows.firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        XCTAssertTrue(keyboard.waitForExistence(timeout: timeout))

        var previousMeasurement: (gap: CGFloat, sheetHeight: CGFloat)?
        var stableSamples = 0
        var gap: CGFloat = 0
        var sheetHeight: CGFloat = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && stableSamples < 2 {
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
            if stableSamples < 2 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
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
        XCTAssertTrue(
            focusedElement.waitForExistence(timeout: timeout),
            "Text field did not acquire keyboard focus: \(element)"
        )
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
