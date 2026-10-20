import Foundation
import Observation

@testable import WhoGaveWhat

@MainActor
@Observable
final class TestPreferencesGateway: PreferencesGateway {
    var didCompleteOnboarding = false
    var currencyCode = "USD"
    var selfPersonID: String?
    var cloudIconConsent: CloudIconConsent = .undecided
    var installID = UUID().uuidString
    func setCloudIconConsent(_ consent: CloudIconConsent) {
        if cloudIconConsent != consent, consent == .declined { installID = UUID().uuidString }
        cloudIconConsent = consent
    }
    func setDidCompleteOnboarding(_ completed: Bool) {
        didCompleteOnboarding = completed
    }
    func setCurrencyCode(_ currencyCode: String) {
        self.currencyCode = currencyCode
    }
    func setSelfPersonID(_ id: String?) {
        selfPersonID = id
    }
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
    selfPersonID: String? = SwiftDataStore.seedSelfPersonID
) throws -> AppComposition {
    let preferences = TestPreferencesGateway()
    preferences.selfPersonID = selfPersonID
    return AppComposition(
        store: try SwiftDataStore(inMemory: true, seed: true),
        preferences: preferences,
        intelligence: TestIntelligenceGateway()
    )
}

@MainActor
func makeSaveGiftUseCase() -> (SaveGiftUseCase, TestGiftGateway) {
    let gateway = TestGiftGateway()
    let suggestions = SuggestGiftUseCase(intelligenceGateway: TestIntelligenceGateway())
    return (SaveGiftUseCase(giftGateway: gateway, suggestGift: suggestions), gateway)
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
