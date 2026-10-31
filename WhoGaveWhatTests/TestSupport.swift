import Foundation
import Observation

@testable import WhoGaveWhat

@MainActor
@Observable
final class TestPreferencesGateway: PreferencesGateway {
    var currencyCode = "USD"
    var selfPersonID: String?
    var cloudIconConsent: CloudIconConsent = .undecided
    var installID = UUID().uuidString
    var analyticsEnabled = true
    func setAnalyticsEnabled(_ enabled: Bool) {
        analyticsEnabled = enabled
    }
    func setCloudIconConsent(_ consent: CloudIconConsent) {
        if cloudIconConsent != consent, consent == .declined { installID = UUID().uuidString }
        cloudIconConsent = consent
    }
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
}

/// Remembers every analytics call for assertions.
@MainActor
final class RecordingAnalyticsGateway: AnalyticsGateway {
    var events: [AnalyticsEvent] = []
    var failures: [AnalyticsFailure] = []
    var contexts: [AnalyticsContext] = []
    var enabledChanges: [Bool] = []

    func track(_ event: AnalyticsEvent) { events.append(event) }
    func report(_ failure: AnalyticsFailure) { failures.append(failure) }
    func update(_ context: AnalyticsContext) { contexts.append(context) }
    func setEnabled(_ enabled: Bool) { enabledChanges.append(enabled) }

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
