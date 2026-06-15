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
}
