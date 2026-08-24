import Testing
@testable import WhoGaveWhat

@MainActor
struct SuggestionTests {
    private func suggest(_ name: String) -> GiftSuggestion {
        SuggestGiftUseCase(intelligenceGateway: TestIntelligenceGateway())
            .instantSuggestion(for: name)
    }

    @Test func matchesAKeyword() {
        let result = suggest("Bouquet of roses")
        #expect(result.emoji == "💐")
        #expect(result.value == 1800)
    }

    @Test func isCaseInsensitive() {
        #expect(suggest("WINE").emoji == "🍷")
        #expect(suggest("WINE").value == 1900)
    }

    @Test func matchesOnSubstring() {
        let result = suggest("new iPhone 15 Pro")
        #expect(result.emoji == "📱")
        #expect(result.value == 40000)
    }

    @Test func fallsBackToGenericGift() {
        let result = suggest("zzz totally unknown thing")
        #expect(result.emoji == "🎁")
        #expect(result.value == 2000)
    }

    @Test func matchesRussianKeywords() {
        #expect(suggest("Букет роз").emoji == "💐")
        #expect(suggest("Шоколадка").emoji == "🍫")
        #expect(suggest("Наушники").emoji == "🎧")
        #expect(suggest("Конверт с деньгами").emoji == "💸")
    }

    @Test func russianToyBeatsGame() {
        #expect(suggest("Мягкая игрушка").emoji == "🧸")
        #expect(suggest("Настольная игра").emoji == "🎮")
    }
}
