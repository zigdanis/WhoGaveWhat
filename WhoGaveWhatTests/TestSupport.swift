@testable import WhoGaveWhat

@MainActor
final class TestPreferencesGateway: PreferencesGateway {
    var didCompleteOnboarding = false
    func setDidCompleteOnboarding(_ completed: Bool) {
        didCompleteOnboarding = completed
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
    func deleteGifts(involving personID: String) throws {
        gifts.removeAll { $0.personId == personID || $0.memberId == personID }
    }
}

@MainActor
func makeTestComposition() -> AppComposition {
    AppComposition(
        stack: CoreDataStack(inMemory: true, seed: true),
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
        value: value, aiValue: nil, valueTouched: valueTouched,
        fromID: fromID, toID: toID, paidByYou: paidByYou,
        celebration: nil, date: AppDate.today
    )
}
