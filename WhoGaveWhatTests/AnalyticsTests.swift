import Foundation
import Testing

@testable import WhoGaveWhat

@MainActor
struct AnalyticsEventCatalogTests {
    private static let sample: [AnalyticsEvent] = [
        .tabSelected(tab: "people"),
        .giftSheetOpened(mode: .create, source: .welcomeCard),
        .giftSheetClosed(mode: .edit, outcome: .saved),
        .giftDetailViewed,
        .personDetailViewed(isSelf: true, giftsCount: 3),
        .openedFromSpotlight,
        .giftPickerOpened(.icon),
        .giftIconPicked(custom: true),
        .giftPriceEdited(hadEstimate: false),
        .giftSuggestionCompleted(provider: .cloud, hasIcon: true, hasPrice: false, latencyMilliseconds: 420),
        .occasionAdded,
        .cloudIconsConsentChanged(allowed: true, source: .addGift),
        .giftSaved(
            GiftSavedProperties(
                mode: .create, direction: .received, iconSource: .inferred, valueSource: .estimate,
                occasion: "birthday", paidByYou: false, dateOffset: .today, giftsCount: 1)),
        .giftDeleted(source: .home, giftsCount: 0),
        .personCreated(source: .giftPicker, peopleCount: 2),
        .personUpdated(nameChanged: true, photo: .added),
        .personDeleted(source: .peopleList, giftsRemoved: 4, peopleCount: 1),
        .viewpointChanged(isSet: true),
        .insightsPersonPicked(slot: "subject"),
        .insightsYearChanged(isCurrentYear: false),
        .currencyChanged(currency: "USD"),
        .privacyPolicyOpened,
        .licensesOpened,
        .analyticsConsentChanged(enabled: false)
    ]

    @Test func namesAndPropertyKeysAreSnakeCaseAndUnique() {
        let snakeCase = #/^[a-z][a-z0-9_]*$/#
        var seen = Set<String>()
        for event in Self.sample {
            #expect(event.name.wholeMatch(of: snakeCase) != nil, "\(event.name)")
            #expect(seen.insert(event.name).inserted, "duplicate \(event.name)")
            for key in event.properties.keys {
                #expect(key.wholeMatch(of: snakeCase) != nil, "\(event.name).\(key)")
            }
        }
    }

    @Test func propertiesCarryCategoriesNotText() {
        let event = AnalyticsEvent.giftSuggestionCompleted(provider: .onDevice, hasIcon: false, hasPrice: true, latencyMilliseconds: 90)
        #expect(event.properties["provider"] == .string("on_device"))
        #expect(event.properties["outcome"] == .string("suggested"))
        #expect(event.properties["latency_ms"] == .int(90))
        #expect(AnalyticsEvent.giftIconPicked(custom: false).properties["source"] == .string("list"))
        #expect(AnalyticsEvent.cloudIconsConsentChanged(allowed: false, source: .settings).properties["consent"] == .string("declined"))
    }

    @Test func occasionLabelKeepsBuiltInsAndHidesCustomText() {
        let defaults = AppData.defaultOccasions.map(\.name)
        #expect(GiftSavedProperties.occasionLabel("Just because", defaults: defaults) == "just_because")
        #expect(GiftSavedProperties.occasionLabel("New Year", defaults: defaults) == "new_year")
        #expect(GiftSavedProperties.occasionLabel("Grandma's 80th", defaults: defaults) == "custom")
    }

    @Test func dateOffsetBuckets() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        #expect(GiftDateOffset.bucket(for: day(0), today: today, calendar: calendar) == .today)
        #expect(GiftDateOffset.bucket(for: day(-1), today: today, calendar: calendar) == .pastWeek)
        #expect(GiftDateOffset.bucket(for: day(-7), today: today, calendar: calendar) == .pastWeek)
        #expect(GiftDateOffset.bucket(for: day(-8), today: today, calendar: calendar) == .pastMonth)
        #expect(GiftDateOffset.bucket(for: day(-31), today: today, calendar: calendar) == .pastMonth)
        #expect(GiftDateOffset.bucket(for: day(-32), today: today, calendar: calendar) == .older)
        #expect(GiftDateOffset.bucket(for: day(3), today: today, calendar: calendar) == .future)
    }
}

@MainActor
struct CompositionAnalyticsTests {
    @Test func savingTracksTheGiftShapeAndRefreshesTheContext() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)
        let giftsBefore = composition.data.gifts.count
        var input = makeGiftInput(name: "Scarf", fromID: "maria", toID: SwiftDataStore.seedSelfPersonID)
        input.estimatedValue = 1_200
        input.occasion = "Birthday"

        #expect(composition.saveGift(input))

        let saved = try #require(analytics.events.last)
        #expect(saved.name == "gift_saved")
        #expect(saved.properties["mode"] == .string("create"))
        #expect(saved.properties["direction"] == .string("received"))
        #expect(saved.properties["icon_source"] == .string("inferred"))
        #expect(saved.properties["value_source"] == .string("estimate"))
        #expect(saved.properties["occasion"] == .string("birthday"))
        #expect(saved.properties["gifts_count"] == .int(giftsBefore + 1))
        #expect(analytics.contexts.last?.giftsCount == giftsBefore + 1)
        #expect(analytics.failures.isEmpty)
    }

    @Test func invalidSaveTracksNothing() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)

        #expect(!composition.saveGift(makeGiftInput(name: "", fromID: "maria", toID: "anton")))

        #expect(analytics.events.isEmpty)
    }

    @Test func editingAndDeletingAreTrackedWithTheirSources() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)
        let gift = try #require(composition.data.gifts.first)
        var input = makeGiftInput(name: gift.name, fromID: gift.giverID, toID: gift.recipientID, value: 500, valueTouched: true)
        input.editingGiftID = gift.id
        input.emoji = "🎁"

        composition.saveGift(input)
        composition.deleteGift(id: gift.id, source: .giftDetail)

        #expect(analytics.eventNames == ["gift_saved", "gift_deleted"])
        #expect(analytics.events[0].properties["mode"] == .string("edit"))
        #expect(analytics.events[0].properties["icon_source"] == .string("user"))
        #expect(analytics.events[0].properties["value_source"] == .string("user"))
        #expect(analytics.events[1].properties["source"] == .string("gift_detail"))
        #expect(analytics.events[1].properties["gifts_count"] == .int(composition.data.gifts.count))
    }

    @Test func peopleEventsCountOnlyRealChanges() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)
        let existing = try #require(composition.data.people.first)

        _ = composition.createPerson(name: existing.name, source: .giftPicker)
        #expect(analytics.events.isEmpty)

        let id = try #require(composition.createPerson(name: "Dana", source: .peopleTab))
        #expect(analytics.events.last == .personCreated(source: .peopleTab, peopleCount: composition.data.people.count))

        try composition.updatePerson(id: id, name: "Dana", imageData: Data([1, 2, 3]))
        #expect(analytics.events.last == .personUpdated(nameChanged: false, photo: .added))

        try composition.updatePerson(id: id, name: "Dana K", imageData: Data([1, 2, 3]))
        #expect(analytics.events.last == .personUpdated(nameChanged: true, photo: .unchanged))

        composition.deletePerson(id: id, source: .personEditor)
        #expect(analytics.events.last == .personDeleted(source: .personEditor, giftsRemoved: 0, peopleCount: composition.data.people.count))
        #expect(analytics.failures.isEmpty)
    }

    @Test func duplicateNameIsNotReportedAsAFailure() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)
        let people = composition.data.people
        let first = try #require(people.first)
        let second = try #require(people.dropFirst().first)

        #expect(throws: PersonUpdateError.self) {
            try composition.updatePerson(id: first.id, name: second.name, imageData: nil)
        }

        #expect(analytics.failures.isEmpty)
        #expect(analytics.events.isEmpty)
    }

    @Test func viewpointCurrencyAndConsentChangesAreTracked() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(selfPersonID: nil, analytics: analytics)

        composition.markSelf(true, personID: "anton")
        composition.markSelf(true, personID: "anton")
        composition.markSelf(false, personID: "anton")
        composition.setCurrencyCode("RUB")
        composition.setCurrencyCode("RUB")
        composition.setCloudIconConsent(.allowed)
        composition.setCloudIconConsent(.declined, source: .settings)

        #expect(
            analytics.events == [
                .viewpointChanged(isSet: true),
                .viewpointChanged(isSet: false),
                .currencyChanged(currency: "RUB"),
                .cloudIconsConsentChanged(allowed: true, source: .settings),
                .cloudIconsConsentChanged(allowed: false, source: .settings)
            ])
        #expect(analytics.contexts.last?.cloudIcons == "declined")
        #expect(analytics.contexts.last?.hasViewpoint == false)
    }

    @Test func turningAnalyticsOffSendsTheChoiceLastAndPersistsIt() throws {
        let analytics = RecordingAnalyticsGateway()
        let preferences = TestPreferencesGateway()
        let composition = AppComposition(
            store: try SwiftDataStore(inMemory: true),
            preferences: preferences,
            intelligence: TestIntelligenceGateway(),
            analytics: analytics
        )
        #expect(composition.isAnalyticsEnabled)

        composition.setAnalyticsEnabled(false)
        composition.setAnalyticsEnabled(false)
        composition.setAnalyticsEnabled(true)

        #expect(!analytics.events.isEmpty)
        #expect(analytics.events == [.analyticsConsentChanged(enabled: false), .analyticsConsentChanged(enabled: true)])
        #expect(analytics.enabledChanges == [false, true])
        #expect(preferences.analyticsEnabled)
        #expect(composition.isAnalyticsEnabled)
    }

    @Test func spotlightLaunchIsTrackedOnlyWhenRecognized() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)

        #expect(!composition.continueAppDiscovery(NSUserActivity(activityType: "other")))
        #expect(analytics.events.isEmpty)
    }

    @Test func photoChangeClassification() {
        #expect(AppComposition.photoChange(from: nil, to: nil) == .unchanged)
        #expect(AppComposition.photoChange(from: nil, to: Data([1])) == .added)
        #expect(AppComposition.photoChange(from: Data([1]), to: nil) == .removed)
        #expect(AppComposition.photoChange(from: Data([1]), to: Data([1])) == .unchanged)
        #expect(AppComposition.photoChange(from: Data([1]), to: Data([2])) == .replaced)
    }

    @Test func userDefaultsGatewayDefaultsAnalyticsOnAndPersistsOff() {
        let suiteName = "AnalyticsPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let gateway = UserDefaultsPreferencesGateway(defaults: defaults)

        #expect(gateway.analyticsEnabled)
        gateway.setAnalyticsEnabled(false)

        #expect(!UserDefaultsPreferencesGateway(defaults: defaults).analyticsEnabled)
    }
}

@MainActor
struct RouterAnalyticsTests {
    @Test func tabsAndSheetsAreTrackedOnce() {
        let analytics = RecordingAnalyticsGateway()
        let router = AppRouter(launchEnvironment: [:], analytics: analytics)

        router.selectTab(.people)
        router.selectTab(.people)
        router.presentNewGift(from: .floatingButton)
        router.dismissGiftSheet()
        router.dismissGiftSheet()
        router.presentEditGift(id: "g1")
        router.dismissGiftSheet(outcome: .saved)

        #expect(
            analytics.events == [
                .tabSelected(tab: "people"),
                .giftSheetOpened(mode: .create, source: .floatingButton),
                .giftSheetClosed(mode: .create, outcome: .cancelled),
                .giftSheetOpened(mode: .edit, source: .giftDetail),
                .giftSheetClosed(mode: .edit, outcome: .saved)
            ])
    }

    @Test func verificationLaunchSheetIsNotAnEvent() {
        let analytics = RecordingAnalyticsGateway()
        let router = AppRouter(launchEnvironment: ["KS_SHEET": "1", "KS_TAB": "people"], analytics: analytics)

        #expect(router.giftSheet == .create)
        #expect(router.tab == .people)
        #expect(analytics.events.isEmpty)
    }
}

@MainActor
struct AddGiftStateAnalyticsTests {
    @Test func pickersIconsAndPriceEditsAreTracked() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition()
        let state = AddGiftState(
            route: .create,
            data: composition.data,
            suggestGift: composition.suggestGift,
            analytics: analytics
        )

        state.open(.from)
        state.open(.emoji)
        state.selectEmoji("🎸")
        state.useCustomEmoji("Ж")
        state.draft.estimatedValue = 900
        state.valueText = "1"
        state.valueText = "12"

        #expect(
            analytics.events == [
                .giftPickerOpened(.giver),
                .giftPickerOpened(.icon),
                .giftIconPicked(custom: false),
                .giftIconPicked(custom: true),
                .giftPriceEdited(hadEstimate: true)
            ])
    }

    @Test func editingAStoredPriceIsTrackedOnceWithoutAnEstimate() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition()
        let gift = try #require(composition.data.gifts.first)
        let state = AddGiftState(
            route: .edit(giftID: gift.id), data: composition.data, suggestGift: composition.suggestGift, analytics: analytics)

        state.valueText = "7"
        state.valueText = "70"

        #expect(analytics.events == [.giftPriceEdited(hadEstimate: false)])
    }

    @Test func savingClosesTheSheetAsSaved() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)
        composition.router.presentNewGift(from: .welcomeCard)
        composition.router.tab = .people
        let state = AddGiftState(route: .create, data: composition.data, suggestGift: composition.suggestGift, analytics: analytics)
        state.name = "Scarf"
        state.selectFrom("maria")
        state.selectTo("anton")

        state.save(using: composition)

        #expect(composition.router.giftSheet == nil)
        #expect(composition.router.tab == .home)
        #expect(Array(analytics.eventNames.suffix(2)) == ["gift_saved", "gift_sheet_closed"])
        #expect(analytics.events.last == .giftSheetClosed(mode: .create, outcome: .saved))
        #expect(!analytics.eventNames.dropFirst().contains("tab_selected"))
    }
}

@MainActor
struct CrashReportSanitizingTests {
    @Test func reportedErrorsKeepOnlyDomainCodeAndType() {
        let error = SwiftDataPersistenceError.missingPerson(endpoint: .giver, id: "Aunt Maria")
        let sanitized = SentryCrashReportingGateway.sanitized(error)

        #expect(sanitized.domain == (error as NSError).domain)
        #expect(sanitized.code == (error as NSError).code)
        #expect(Set(sanitized.userInfo.keys) == [NSLocalizedDescriptionKey])
        #expect(sanitized.localizedDescription.contains("SwiftDataPersistenceError"))
        #expect(!sanitized.localizedDescription.contains("Maria"))
    }

    @Test func cloudIconConsentFromTheSheetGoesThroughTheComposition() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)
        let state = AddGiftState(
            route: .create, data: composition.data, suggestGift: composition.suggestGift,
            preferences: composition.preferences, analytics: analytics,
            applyCloudIconConsent: { composition.setCloudIconConsent($0, source: .addGift) })

        state.allowCloudIcons()

        #expect(composition.cloudIconConsent == .allowed)
        #expect(analytics.events == [.cloudIconsConsentChanged(allowed: true, source: .addGift)])
        #expect(analytics.contexts.last?.cloudIcons == "allowed")
    }
}

struct MonitoringConfigurationTests {
    @Test func readsKeysAndTreatsEmptyValuesAsAbsent() {
        let configuration = MonitoringConfiguration.current(
            info: [
                MonitoringConfiguration.postHogAPIKeyInfoKey: "phc_test",
                MonitoringConfiguration.postHogHostInfoKey: " ",
                MonitoringConfiguration.sentryDSNInfoKey: ""
            ],
            launchEnvironment: [:],
            receiptURL: URL(fileURLWithPath: "/receipts/sandboxReceipt"))

        #expect(configuration.postHogAPIKey == "phc_test")
        #expect(configuration.postHogHost == MonitoringConfiguration.defaultPostHogHost)
        #expect(configuration.sentryDSN == nil)
        #expect(configuration.isPostHogConfigured)
        #expect(!configuration.isSentryConfigured)
        #expect(configuration.isTestFlight)
    }

    @Test func onlyReleaseDeviceLaunchesWithoutVerificationFlagsReport() {
        func configuration(debug: Bool, simulator: Bool, environment: [String: String]) -> MonitoringConfiguration {
            MonitoringConfiguration(
                postHogAPIKey: "phc_test", sentryDSN: "https://key@sentry.example/1",
                isDebugBuild: debug, isSimulator: simulator,
                isVerificationLaunch: MonitoringConfiguration.isVerificationLaunch(environment), isTestFlight: false)
        }
        #expect(configuration(debug: false, simulator: false, environment: ["PATH": "/usr/bin"]).isReportingAllowed)
        #expect(!configuration(debug: true, simulator: false, environment: [:]).isReportingAllowed)
        #expect(!configuration(debug: false, simulator: true, environment: [:]).isReportingAllowed)
        #expect(!configuration(debug: false, simulator: false, environment: ["KS_START": "app"]).isReportingAllowed)
    }

    @Test func environmentNameFollowsBuildAndReceipt() {
        #expect(
            MonitoringConfiguration(isDebugBuild: true, isSimulator: false, isVerificationLaunch: false, isTestFlight: true)
                .environmentName == "debug")
        #expect(
            MonitoringConfiguration(isDebugBuild: false, isSimulator: false, isVerificationLaunch: false, isTestFlight: true)
                .environmentName == "testflight")
        #expect(
            MonitoringConfiguration(isDebugBuild: false, isSimulator: false, isVerificationLaunch: false, isTestFlight: false)
                .environmentName == "appstore")
    }

    @MainActor
    @Test func unconfiguredReleaseLaunchGetsTheSilentGateway() {
        let configuration = MonitoringConfiguration(isDebugBuild: false, isSimulator: false, isVerificationLaunch: false, isTestFlight: false)
        #expect(Monitoring.makeAnalytics(configuration: configuration, isEnabled: true) is NoopAnalyticsGateway)
    }
}
