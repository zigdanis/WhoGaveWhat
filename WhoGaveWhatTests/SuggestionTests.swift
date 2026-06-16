import Testing
@testable import WhoGaveWhat

/// `AppStore.suggest` maps a gift name to an emoji + guessed value.
@MainActor
struct SuggestionTests {

    @Test func matchesAKeyword() {
        let store = makeSeededStore()
        let s = store.suggest("Bouquet of roses")
        #expect(s.emoji == "💐")
        #expect(s.value == 1800)
    }

    @Test func isCaseInsensitive() {
        let store = makeSeededStore()
        #expect(store.suggest("WINE").emoji == "🍷")
        #expect(store.suggest("WINE").value == 1900)
    }

    @Test func matchesOnSubstring() {
        let store = makeSeededStore()
        let s = store.suggest("new iPhone 15 Pro")
        #expect(s.emoji == "📱")
        #expect(s.value == 40000)
    }

    @Test func fallsBackToGenericGift() {
        let store = makeSeededStore()
        let s = store.suggest("zzz totally unknown thing")
        #expect(s.emoji == "🎁")
        #expect(s.value == 2000)
    }

    @Test func matchesRussianKeywords() {
        let store = makeSeededStore()
        #expect(store.suggest("Букет роз").emoji == "💐")
        #expect(store.suggest("Шоколадка").emoji == "🍫")
        #expect(store.suggest("Наушники").emoji == "🎧")
        #expect(store.suggest("Конверт с деньгами").emoji == "💸")
    }

    /// Toys ("игрушка") must win over games ("игра") since the toy entry is
    /// listed first — guards the ordering documented on `suggestMap`.
    @Test func russianToyBeatsGame() {
        let store = makeSeededStore()
        #expect(store.suggest("Мягкая игрушка").emoji == "🧸")
        #expect(store.suggest("Настольная игра").emoji == "🎮")
    }
}
