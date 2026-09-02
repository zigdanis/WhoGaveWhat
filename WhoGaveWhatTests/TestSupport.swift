@testable import WhoGaveWhat

@MainActor
final class TestPreferencesGateway: PreferencesGateway {
    var didCompleteOnboarding = false
    var currencyCode = "USD"
    func setDidCompleteOnboarding(_ completed: Bool) {
        didCompleteOnboarding = completed
    }
    func setCurrencyCode(_ currencyCode: String) {
        self.currencyCode = currencyCode
    }
}

@MainActor
final class TestIntelligenceGateway: GiftIntelligenceGateway {
    var isAvailable = false
    func suggestGift(named name: String) async -> GiftIntelligenceResult? { nil }
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
func makeTestComposition() -> AppComposition {
    AppComposition(
        store: try! SwiftDataStore(inMemory: true, seed: true),
        preferences: TestPreferencesGateway(),
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
