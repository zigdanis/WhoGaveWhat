import Foundation
import Observation

@testable import WhoGaveWhat

@MainActor
@Observable
final class TestPreferencesGateway: PreferencesGateway {
    var currencyCode = "USD"
    var selfPersonID: String?
    var installID = UUID().uuidString
    func setCurrencyCode(_ currencyCode: String) {
        self.currencyCode = currencyCode
    }
    func setSelfPersonID(_ id: String?) {
        selfPersonID = id
    }
    var recentInsightsPicks: [InsightsPickerSlot: [String]] = [:]
    func recentInsightsPicks(for slot: InsightsPickerSlot) -> [String] {
        recentInsightsPicks[slot] ?? []
    }
    func setRecentInsightsPicks(_ ids: [String], for slot: InsightsPickerSlot) {
        recentInsightsPicks[slot] = ids
    }
    var reviewPromptState = ReviewPromptState()
    func setReviewPromptState(_ state: ReviewPromptState) {
        reviewPromptState = state
    }
}

/// Remembers every analytics call for assertions.
@MainActor
final class RecordingAnalyticsGateway: AnalyticsGateway {
    var events: [AnalyticsEvent] = []
    var failures: [AnalyticsFailure] = []
    var contexts: [AnalyticsContext] = []

    func track(_ event: AnalyticsEvent) { events.append(event) }
    func report(_ failure: AnalyticsFailure) { failures.append(failure) }
    func update(_ context: AnalyticsContext) { contexts.append(context) }

    var eventNames: [String] { events.map(\.name) }
}

/// Remembers every haptic request for assertions.
@MainActor
final class RecordingHapticsGateway: HapticsGateway {
    var played: [HapticFeedback] = []

    func play(_ feedback: HapticFeedback) { played.append(feedback) }
}

@MainActor
final class TestIntelligenceGateway: GiftIntelligenceGateway {
    var isAvailable = false
    func prewarm() {}
    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult? { nil }
}

@MainActor
final class TestGiftGateway: GiftGateway {
    var gifts: [Gift]

    init(gifts: [Gift] = []) { self.gifts = gifts }

    func loadGifts() throws -> [Gift] { gifts }
    func save(_ gift: Gift) throws {
        gifts.removeAll { $0.id == gift.id }
        gifts.append(gift)
    }
    func deleteGift(id: String) throws { gifts.removeAll { $0.id == id } }
}

@MainActor
func makeTestComposition(
    selfPersonID: String? = SwiftDataStore.seedSelfPersonID,
    analytics: AnalyticsGateway = NoopAnalyticsGateway(),
    haptics: HapticsGateway = NoopHapticsGateway()
) throws -> AppComposition {
    let preferences = TestPreferencesGateway()
    preferences.selfPersonID = selfPersonID
    return AppComposition(
        store: try SwiftDataStore(inMemory: true, seed: true),
        preferences: preferences,
        intelligence: TestIntelligenceGateway(),
        analytics: analytics,
        haptics: haptics
    )
}

@MainActor
func makeSaveGiftUseCase(
    now: @escaping () -> Date = { Date() }
) -> (SaveGiftUseCase, TestGiftGateway) {
    let gateway = TestGiftGateway()
    let suggestions = SuggestGiftUseCase(intelligenceGateway: TestIntelligenceGateway())
    return (SaveGiftUseCase(giftGateway: gateway, suggestGift: suggestions, now: now), gateway)
}

func makeGiftInput(
    name: String = "",
    fromID: String? = nil,
    toID: String? = nil,
    value: Int? = nil,
    valueTouched: Bool = false,
    paidByYou: Bool = false
) -> SaveGiftInput {
    SaveGiftInput(
        editingGiftID: nil, name: name, emoji: nil, aiEmoji: nil,
        value: value, valueTouched: valueTouched,
        fromID: fromID, toID: toID, paidByYou: paidByYou,
        occasion: nil, date: AppDate.today, createdAt: nil
    )
}

/// The error a failing fake throws. Like a sanitized store error, it carries no user data.
struct TestWriteFailure: Error {}

/// Wraps a real gift gateway and refuses the next `failingSaves` saves and `failingDeletes` deletions
/// without writing anything, like SwiftData rolling back a failed save.
@MainActor
final class FailingGiftGateway: GiftGateway {
    private let base: GiftGateway
    var failingSaves = 0
    var failingDeletes = 0

    init(base: GiftGateway) { self.base = base }

    func loadGifts() throws -> [Gift] { try base.loadGifts() }

    func save(_ gift: Gift) throws {
        if failingSaves > 0 {
            failingSaves -= 1
            throw TestWriteFailure()
        }
        try base.save(gift)
    }

    func deleteGift(id: String) throws {
        if failingDeletes > 0 {
            failingDeletes -= 1
            throw TestWriteFailure()
        }
        try base.deleteGift(id: id)
    }
}

/// Wraps a real people gateway and refuses the next `failingDeletes` deletions without writing anything.
@MainActor
final class FailingPeopleGateway: PeopleGateway {
    private let base: PeopleGateway
    var failingDeletes = 0

    init(base: PeopleGateway) { self.base = base }

    func loadPeople() throws -> PeopleSnapshot { try base.loadPeople() }

    func createPerson(id: String, name: String, colorHex: UInt, sortIndex: Int) throws {
        try base.createPerson(id: id, name: name, colorHex: colorHex, sortIndex: sortIndex)
    }

    func renamePerson(id: String, name: String) throws { try base.renamePerson(id: id, name: name) }

    func updatePerson(id: String, name: String, imageData: Data?) throws {
        try base.updatePerson(id: id, name: name, imageData: imageData)
    }

    func deletePerson(id: String) throws {
        if failingDeletes > 0 {
            failingDeletes -= 1
            throw TestWriteFailure()
        }
        try base.deletePerson(id: id)
    }
}

/// A seeded in-memory composition whose writes can be made to fail, plus direct read access to its store.
@MainActor
struct FailableComposition {
    let composition: AppComposition
    let gifts: FailingGiftGateway
    let people: FailingPeopleGateway
    let preferences: TestPreferencesGateway
    private let store: SwiftDataStore

    init(
        selfPersonID: String? = SwiftDataStore.seedSelfPersonID,
        launchEnvironment: [String: String] = [:],
        analytics: AnalyticsGateway = NoopAnalyticsGateway(),
        haptics: HapticsGateway = NoopHapticsGateway()
    ) throws {
        store = try SwiftDataStore(inMemory: true, seed: true)
        preferences = TestPreferencesGateway()
        preferences.selfPersonID = selfPersonID
        gifts = FailingGiftGateway(base: SwiftDataGiftGateway(context: store.context))
        people = FailingPeopleGateway(base: SwiftDataPeopleGateway(context: store.context))
        composition = AppComposition(
            store: store,
            preferences: preferences,
            intelligence: TestIntelligenceGateway(),
            launchEnvironment: launchEnvironment,
            analytics: analytics,
            haptics: haptics,
            giftGateway: gifts,
            peopleGateway: people
        )
    }

    /// What the store holds right now, read past the composition's cached data.
    func storedGifts() throws -> [Gift] { try SwiftDataGiftGateway(context: store.context).loadGifts() }
    func storedPeople() throws -> [Person] { try SwiftDataPeopleGateway(context: store.context).loadPeople().people }
}
