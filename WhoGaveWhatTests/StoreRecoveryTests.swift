import Foundation
import Testing

@testable import WhoGaveWhat

private struct TestStoreError: Error {}

/// A gift gateway whose loads fail while `loadError` is set.
@MainActor
private final class ScriptedGiftGateway: GiftGateway {
    var gifts: [Gift]
    var loadError: Error?

    init(gifts: [Gift] = [], loadError: Error? = nil) {
        self.gifts = gifts
        self.loadError = loadError
    }

    func loadGifts() throws -> [Gift] {
        if let loadError { throw loadError }
        return gifts
    }
    func save(_ gift: Gift) throws {
        gifts.removeAll { $0.id == gift.id }
        gifts.append(gift)
    }
    func deleteGift(id: String) throws { gifts.removeAll { $0.id == id } }
}

/// A people gateway whose loads fail while `loadError` is set.
@MainActor
private final class ScriptedPeopleGateway: PeopleGateway {
    var people: [Person]
    var loadError: Error?

    init(people: [Person] = [], loadError: Error? = nil) {
        self.people = people
        self.loadError = loadError
    }

    func loadPeople() throws -> PeopleSnapshot {
        if let loadError { throw loadError }
        return PeopleSnapshot(people: people)
    }
    func createPerson(id: String, name: String, colorHex: UInt, sortIndex: Int) throws {
        people.append(Person(id: id, name: name, colorHex: colorHex))
    }
    func renamePerson(id: String, name: String) throws {}
    func updatePerson(id: String, name: String, imageData: Data?) throws {}
    func deletePerson(id: String) throws { people.removeAll { $0.id == id } }
}

private func person(_ id: String) -> Person {
    Person(id: id, name: id.capitalized, colorHex: 0x12805C)
}

private func gift(_ id: String, from giverID: String, to recipientID: String) -> Gift {
    Gift(
        id: id, emoji: "🎁", name: "Gift \(id)", giverID: giverID, recipientID: recipientID, paidByYou: false,
        occasion: "Birthday", date: Date(timeIntervalSince1970: 1_000), value: 10,
        createdAt: Date(timeIntervalSince1970: 1_000))
}

@MainActor
struct DataLoadRecoveryTests {
    private func makeComposition(
        gifts: ScriptedGiftGateway, people: ScriptedPeopleGateway, selfPersonID: String? = nil,
        analytics: AnalyticsGateway = NoopAnalyticsGateway(), haptics: HapticsGateway = NoopHapticsGateway()
    ) -> (AppComposition, TestPreferencesGateway) {
        let preferences = TestPreferencesGateway()
        preferences.selfPersonID = selfPersonID
        let composition = AppComposition(
            giftGateway: gifts, peopleGateway: people, preferences: preferences,
            intelligence: TestIntelligenceGateway(), launchEnvironment: [:], analytics: analytics, haptics: haptics)
        return (composition, preferences)
    }

    @Test func failedInitialLoadIsNotAnEmptyJournal() {
        let analytics = RecordingAnalyticsGateway()
        let gifts = ScriptedGiftGateway(gifts: [gift("g1", from: "me", to: "ann")], loadError: TestStoreError())
        let people = ScriptedPeopleGateway(people: [person("me"), person("ann")])
        let (composition, preferences) = makeComposition(
            gifts: gifts, people: people, selfPersonID: "me", analytics: analytics)

        #expect(!composition.data.hasLoadedSnapshot)
        #expect(composition.data.isLoadFailing)
        #expect(!composition.data.showsGiftsWelcome)
        #expect(!composition.data.showsPeopleWelcome)
        // An unloaded journal cannot tell that the viewpoint's person is gone.
        #expect(composition.data.selfPersonID == "me")
        #expect(preferences.selfPersonID == "me")
        #expect(analytics.failures.map(\.operation) == ["load_gifts"])
        #expect(analytics.failures.first?.details["has_snapshot"] == .bool(false))
        // No counts travel before the first snapshot, so a report never claims an empty journal.
        #expect(analytics.contexts.isEmpty)
    }

    @Test func partialInitialLoadPublishesNothing() {
        let gifts = ScriptedGiftGateway(gifts: [gift("g1", from: "me", to: "ann")])
        let people = ScriptedPeopleGateway(people: [person("me"), person("ann")], loadError: TestStoreError())
        let (composition, _) = makeComposition(gifts: gifts, people: people, selfPersonID: "me")

        #expect(composition.data.gifts.isEmpty)
        #expect(composition.data.people.isEmpty)
        #expect(!composition.data.hasLoadedSnapshot)
        #expect(composition.data.isLoadFailing)
        #expect(!composition.data.showsGiftsWelcome)
        #expect(composition.data.selfPersonID == "me")
    }

    @Test func partialReloadFailureKeepsTheLastSnapshotAndViewpoint() {
        let analytics = RecordingAnalyticsGateway()
        let gifts = ScriptedGiftGateway(gifts: [gift("old", from: "me", to: "ann")])
        let people = ScriptedPeopleGateway(people: [person("me"), person("ann")])
        let (composition, preferences) = makeComposition(
            gifts: gifts, people: people, selfPersonID: "me", analytics: analytics)
        #expect(composition.data.hasLoadedSnapshot)
        #expect(!composition.data.isLoadFailing)

        // The next load would bring a new gift and a people list without the viewpoint, but people fail.
        gifts.gifts = [gift("new", from: "bob", to: "ann")]
        people.people = [person("ann"), person("bob")]
        people.loadError = TestStoreError()
        #expect(!composition.reloadData())

        #expect(composition.data.gifts.map(\.id) == ["old"])
        #expect(composition.data.people.map(\.id) == ["me", "ann"])
        #expect(composition.data.selfPersonID == "me")
        #expect(preferences.selfPersonID == "me")
        #expect(composition.data.isLoadFailing)
        #expect(composition.data.hasLoadedSnapshot)
        #expect(analytics.failures.map(\.operation) == ["load_people"])
        #expect(analytics.failures.first?.details["has_snapshot"] == .bool(true))
        #expect(analytics.contexts.last?.giftsCount == 1)
    }

    @Test func retryAfterTheCauseIsFixedPublishesTheRecords() {
        let gifts = ScriptedGiftGateway(gifts: [gift("g1", from: "me", to: "ann")], loadError: TestStoreError())
        let people = ScriptedPeopleGateway(people: [person("me"), person("ann")])
        let (composition, _) = makeComposition(gifts: gifts, people: people, selfPersonID: "me")
        #expect(!composition.data.hasLoadedSnapshot)

        gifts.loadError = nil
        #expect(composition.reloadData())

        #expect(composition.data.gifts.map(\.id) == ["g1"])
        #expect(composition.data.people.map(\.id) == ["me", "ann"])
        #expect(composition.data.hasLoadedSnapshot)
        #expect(!composition.data.isLoadFailing)
        #expect(composition.data.selfPersonID == "me")
    }

    @Test func anEmptySnapshotThatFailedToRefreshIsNotAnEmptyJournal() {
        let gifts = ScriptedGiftGateway()
        let people = ScriptedPeopleGateway()
        let (composition, _) = makeComposition(gifts: gifts, people: people)
        #expect(composition.data.showsGiftsWelcome)
        #expect(composition.data.showsPeopleWelcome)

        // The first gift and person were stored, then the reload after them failed.
        people.people = [person("me"), person("ann")]
        gifts.gifts = [gift("g1", from: "me", to: "ann")]
        gifts.loadError = TestStoreError()
        #expect(!composition.reloadData())

        #expect(!composition.data.showsGiftsWelcome)
        #expect(!composition.data.showsPeopleWelcome)
        #expect(composition.data.isLoadFailing)
    }

    @Test func changesWaitForAFreshSnapshot() throws {
        let analytics = RecordingAnalyticsGateway()
        let haptics = RecordingHapticsGateway()
        let gifts = ScriptedGiftGateway(gifts: [gift("kept", from: "me", to: "ann")])
        let people = ScriptedPeopleGateway(people: [person("me"), person("ann")])
        let (composition, _) = makeComposition(gifts: gifts, people: people, analytics: analytics, haptics: haptics)

        // "Dana" was stored, but the reload after it failed, so the screens still lack her.
        people.people.append(Person(id: "dana", name: "Dana", colorHex: 0x12805C))
        let storedPeople = people.people.map(\.id)
        people.loadError = TestStoreError()
        #expect(!composition.reloadData())

        // While the store keeps failing, every change is refused instead of trusting the old snapshot.
        #expect(composition.createPerson(name: "Dana", source: .peopleTab) == nil)
        #expect(throws: StaleSnapshotError.self) {
            try composition.updatePerson(id: "me", name: "Me", imageData: nil)
        }
        // A refused save is a failed save: the sheet keeps the draft and shows the error.
        analytics.events.removeAll()
        #expect(composition.saveGift(makeGiftInput(name: "Book", fromID: "me", toID: "dana")) == .failed)
        #expect(analytics.eventNames == ["gift_save_attempted", "gift_save_failed"])
        #expect(haptics.played.last == .error)
        // An incomplete form is still invalid, not a failure.
        #expect(composition.saveGift(makeGiftInput(name: "Book")) == .invalid)
        // Refused deletions fail the same way, so the screens keep the record and show the alert.
        #expect(composition.deletePerson(id: "dana", source: .peopleList) == .failed)
        #expect(composition.deleteGift(id: "kept", source: .home) == .failed)
        #expect(haptics.played.suffix(2) == [.error, .error])
        #expect(people.people.map(\.id) == storedPeople)
        #expect(gifts.gifts.map(\.id) == ["kept"])
        #expect(!analytics.eventNames.contains("person_created"))
        #expect(!analytics.eventNames.contains("gift_deleted"))
        #expect(!analytics.eventNames.contains("person_deleted"))
        #expect(!analytics.eventNames.contains("gift_saved"))

        // Once loading works again, the change runs against the fresh snapshot: no second Dana.
        people.loadError = nil
        #expect(composition.createPerson(name: "Dana", source: .peopleTab) == "dana")
        #expect(people.people.map(\.id) == storedPeople)
        #expect(!composition.data.isLoadFailing)
        #expect(composition.data.people.map(\.id) == storedPeople)
    }

    @Test func pickerKeepsTheNameAndSaysSoWhenAddingFails() {
        let picker = PersonPickerState(people: [person("ann")], selectedID: nil)
        _ = picker.updateQuery("Dana")
        var selected: [String] = []

        #expect(picker.createAndSelectPerson(named: "Dana", create: { _ in nil }, select: { selected.append($0) }) == nil)
        #expect(picker.creationFailed)
        #expect(picker.query == "Dana")
        #expect(selected.isEmpty)

        // UIKit can deliver the same text again; that is no new attempt, so the message stays.
        _ = picker.updateQuery("Dana")
        #expect(picker.creationFailed)

        // Trying again with the same name and succeeding clears it.
        #expect(picker.createAndSelectPerson(named: "Dana", create: { _ in "dana" }, select: { selected.append($0) }) == "dana")
        #expect(!picker.creationFailed)
        #expect(selected == ["dana"])

        // Editing the name after a failure clears it too.
        #expect(picker.createAndSelectPerson(named: "Dana", create: { _ in nil }, select: { selected.append($0) }) == nil)
        #expect(picker.creationFailed)
        _ = picker.updateQuery("Dana K")
        #expect(!picker.creationFailed)
    }

    @Test(arguments: [[], ["-KS_STORE_FAULT", "open"]])
    func verificationLaunchArgumentsKeepTheRatingRequestOff(_ arguments: [String]) {
        let preferences = TestPreferencesGateway()
        preferences.reviewPromptState = ReviewPromptState(
            activeDays: 3, lastActiveDay: "2026-11-01", firstActiveDate: Date().addingTimeInterval(-2 * 86_400))
        let gifts = ScriptedGiftGateway(gifts: (1...4).map { gift("g\($0)", from: "ann", to: "me") })
        let people = ScriptedPeopleGateway(people: [person("me"), person("ann")])
        let composition = AppComposition(
            giftGateway: gifts, peopleGateway: people, preferences: preferences,
            intelligence: TestIntelligenceGateway(), launchEnvironment: [:], launchArguments: arguments)

        #expect(composition.saveGift(makeGiftInput(name: "Book", fromID: "ann", toID: "me")) == .saved)
        #expect(composition.isReviewRequestPending == arguments.isEmpty)
    }

    @Test(arguments: ["gift", "person"])
    func aRefusedDeleteStillCancelsAndSuppressesTheRatingRequest(_ target: String) {
        let preferences = TestPreferencesGateway()
        preferences.selfPersonID = "me"
        preferences.reviewPromptState = ReviewPromptState(
            activeDays: 3, lastActiveDay: "2026-11-01", firstActiveDate: Date().addingTimeInterval(-2 * 86_400))
        let gifts = ScriptedGiftGateway(gifts: (1...4).map { gift("g\($0)", from: "ann", to: "me") })
        let people = ScriptedPeopleGateway(people: [person("me"), person("ann"), person("bob")])
        let composition = AppComposition(
            giftGateway: gifts, peopleGateway: people, preferences: preferences,
            intelligence: TestIntelligenceGateway(), launchEnvironment: [:])
        #expect(composition.saveGift(makeGiftInput(name: "Book", fromID: "ann", toID: "me")) == .saved)
        #expect(composition.isReviewRequestPending)

        gifts.loadError = TestStoreError()
        #expect(!composition.reloadData())
        if target == "gift" {
            #expect(composition.deleteGift(id: "g1", source: .home) == .failed)
            #expect(gifts.gifts.contains { $0.id == "g1" })
        } else {
            #expect(composition.deletePerson(id: "bob", source: .peopleList) == .failed)
            #expect(people.people.contains { $0.id == "bob" })
        }
        #expect(!composition.isReviewRequestPending)

        // After recovery the setback still holds for this session.
        gifts.loadError = nil
        #expect(composition.saveGift(makeGiftInput(name: "Scarf", fromID: "ann", toID: "me")) == .saved)
        #expect(!composition.isReviewRequestPending)
    }

    @Test func theViewpointNeedsAPersonFromACurrentSnapshot() {
        let analytics = RecordingAnalyticsGateway()
        let haptics = RecordingHapticsGateway()
        let gifts = ScriptedGiftGateway()
        let people = ScriptedPeopleGateway(people: [person("me"), person("ann"), person("bob")])
        let (composition, preferences) = makeComposition(
            gifts: gifts, people: people, selfPersonID: "me", analytics: analytics, haptics: haptics)

        // Bob was deleted, but the reload after it failed, so he is still on screen.
        people.people.removeAll { $0.id == "bob" }
        people.loadError = TestStoreError()
        #expect(!composition.reloadData())
        composition.markSelf(true, personID: "bob")
        #expect(composition.data.selfPersonID == "me")
        #expect(preferences.selfPersonID == "me")
        #expect(haptics.played.last == .error)
        #expect(!analytics.eventNames.contains("viewpoint_changed"))

        // With loading back, the fresh snapshot shows Bob is gone, so he still cannot be chosen.
        people.loadError = nil
        composition.markSelf(true, personID: "bob")
        #expect(composition.data.selfPersonID == "me")
        #expect(!composition.data.isLoadFailing)

        // Someone who is still there can be.
        composition.markSelf(true, personID: "ann")
        #expect(composition.data.selfPersonID == "ann")
        #expect(preferences.selfPersonID == "ann")
        #expect(analytics.eventNames.last == "viewpoint_changed")

        // Clearing it needs no fresh snapshot.
        people.loadError = TestStoreError()
        #expect(!composition.reloadData())
        composition.markSelf(false, personID: "ann")
        #expect(composition.data.selfPersonID == nil)
    }

    @Test func aCompleteSnapshotStillClearsAMissingViewpoint() {
        let gifts = ScriptedGiftGateway()
        let people = ScriptedPeopleGateway(people: [person("ann")])
        let (composition, preferences) = makeComposition(gifts: gifts, people: people, selfPersonID: "gone")

        #expect(composition.data.selfPersonID == nil)
        #expect(preferences.selfPersonID == nil)
        #expect(composition.data.showsGiftsWelcome)
        #expect(!composition.data.showsPeopleWelcome)
    }
}

@MainActor
struct StoreOpenRecoveryTests {
    private func makeLaunch(
        analytics: AnalyticsGateway = NoopAnalyticsGateway(),
        openStore: @escaping () throws -> SwiftDataStore
    ) -> AppLaunch {
        AppLaunch(
            analytics: analytics, haptics: NoopHapticsGateway(), retryPause: .zero, openStore: openStore,
            makeComposition: { store in
                AppComposition(
                    store: store, preferences: TestPreferencesGateway(), intelligence: TestIntelligenceGateway(),
                    launchEnvironment: [:])
            })
    }

    @Test func aStoreThatFailsToOpenShowsTheFailureInsteadOfTrapping() {
        let analytics = RecordingAnalyticsGateway()
        let launch = makeLaunch(analytics: analytics) { throw TestStoreError() }

        launch.start()

        guard case .failed = launch.state else {
            Issue.record("Expected the failure state, got \(launch.state)")
            return
        }
        #expect(launch.composition == nil)
        #expect(analytics.failures.map(\.operation) == ["open_store"])
        #expect(analytics.failures.first?.details["attempt"] == .int(1))
    }

    @Test func retryOpensTheStoreOnceTheCauseIsFixed() async throws {
        let analytics = RecordingAnalyticsGateway()
        var isAvailable = false
        var opened = 0
        let launch = makeLaunch(analytics: analytics) {
            opened += 1
            guard isAvailable else { throw TestStoreError() }
            return try SwiftDataStore(inMemory: true, seed: true)
        }
        launch.start()
        launch.start()
        #expect(opened == 1)

        await launch.retry()
        guard case .failed = launch.state else {
            Issue.record("A second failure should stay on the failure screen, got \(launch.state)")
            return
        }
        #expect(analytics.failures.map { $0.details["attempt"] } == [.int(1), .int(2)])

        launch.sceneBecameActive()
        isAvailable = true
        await launch.retry()

        let composition = try #require(launch.composition)
        #expect(composition.data.gifts.count == 12)
        #expect(composition.data.people.count == 10)
        #expect(composition.isSceneActive)
        #expect(opened == 3)

        // Retry has nothing to do once the store is open.
        await launch.retry()
        #expect(opened == 3)
    }

    @Test func aDamagedStoreFileIsLeftIntactAndOpensAfterItIsRestored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "\(SwiftDataStore.storeName).store")
        let damaged = Data("This is not a SQLite database. ".utf8 + Array(repeating: 0x42, count: 4_096))
        try damaged.write(to: url)

        let launch = makeLaunch { try SwiftDataStore(url: url) }
        launch.start()
        guard case .failed = launch.state else {
            Issue.record("A damaged store must not open, got \(launch.state)")
            return
        }
        #expect(try Data(contentsOf: url) == damaged)

        await launch.retry()
        guard case .failed = launch.state else {
            Issue.record("Retrying a damaged store must not replace it, got \(launch.state)")
            return
        }
        #expect(try Data(contentsOf: url) == damaged)

        // The user's records come back (for example from a backup) and Retry finds them.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: try StoreFixtures.url(of: StoreFixtures.newest), to: url)
        await launch.retry()

        let composition = try #require(launch.composition)
        #expect(composition.data.gifts.count == StoreFixtures.manifest.dataset.gifts.count)
        #expect(composition.data.people.count == StoreFixtures.manifest.dataset.people.count)
    }

    #if DEBUG
        @Test func debugLaunchFaultsFailOnlyTheFirstAttempt() throws {
            #expect(LaunchFault(environment: [:], arguments: []) == nil)
            #expect(LaunchFault(environment: ["KS_STORE_FAULT": "unknown"], arguments: []) == nil)
            #expect(LaunchFault(environment: [:], arguments: ["App", "-KS_STORE_FAULT"]) == nil)
            #expect(LaunchFault(environment: [:], arguments: ["App", "-KS_STORE_FAULT", "people"])?.kind == .people)
            #expect(
                MonitoringConfiguration.isVerificationLaunch([:], arguments: ["App", "-KS_STORE_FAULT", "open"]))
            #expect(!MonitoringConfiguration.isVerificationLaunch([:], arguments: ["App", "-NSDoubleLocalizedStrings"]))

            let open = try #require(LaunchFault(environment: ["KS_STORE_FAULT": "open"], arguments: []))
                .wrapOpen { try SwiftDataStore(inMemory: true) }
            #expect(throws: LaunchFault.InjectedError.self) { try open() }
            _ = try open()

            let gifts = try #require(LaunchFault(environment: ["KS_STORE_FAULT": "load"], arguments: []))
                .wrap(ScriptedGiftGateway(gifts: [gift("g1", from: "a", to: "b")]))
            #expect(throws: LaunchFault.InjectedError.self) { try gifts.loadGifts() }
            #expect(try gifts.loadGifts().map(\.id) == ["g1"])

            let people = try #require(LaunchFault(environment: ["KS_STORE_FAULT": "people"], arguments: []))
                .wrap(ScriptedPeopleGateway(people: [person("a")]))
            #expect(throws: LaunchFault.InjectedError.self) { try people.loadPeople() }
            #expect(try people.loadPeople().people.map(\.id) == ["a"])
        }
    #endif
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "store-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
