import Testing
@testable import WhoGaveWhat

/// The seeded in-memory store and the value math derived from it.
@MainActor
struct SeededDataTests {

    @Test func seedsTheSampleDataset() {
        let store = makeSeededStore()
        #expect(store.gifts.count == 12)
        #expect(store.members.count == 4)
        #expect(store.people.count == 6)
    }

    @Test func splitsReceivedAndGiven() {
        let store = makeSeededStore()
        #expect(store.received.count == 7)
        #expect(store.given.count == 5)
    }

    @Test func sumsGiftValues() {
        let store = makeSeededStore()
        #expect(store.sum(store.received) == 19300)
        #expect(store.sum(store.given) == 11800)
        #expect(store.sum([]) == 0)
    }
}

/// `canSave` guards the "Add a gift" sheet.
@MainActor
struct AddFormTests {

    @Test func requiresBothNameAndPerson() {
        let store = makeSeededStore()
        #expect(store.canSave() == false)            // blank form

        store.add.name = "Book set"
        #expect(store.canSave() == false)            // no person yet

        store.add.personId = "igor"
        #expect(store.canSave() == true)

        store.add.name = "   "
        #expect(store.canSave() == false)            // whitespace-only name
    }
}

/// Navigation actions move between screens / tabs.
@MainActor
struct NavigationTests {

    @Test func onboardingAdvancesThenLeavesToSignin() {
        let store = makeSeededStore()
        store.screen = .onboarding
        store.onbStep = 0
        store.onbNext(); #expect(store.onbStep == 1)
        store.onbNext(); #expect(store.onbStep == 2)
        store.onbNext(); #expect(store.screen == .signin)
    }

    @Test func skipGoesStraightToSignin() {
        let store = makeSeededStore()
        store.onbSkip()
        #expect(store.screen == .signin)
    }

    @Test func enterAppShowsTheApp() {
        let store = makeSeededStore()
        store.enterApp()
        #expect(store.screen == .app)
    }

    @Test func switchingTabClearsOpenDetail() {
        let store = makeSeededStore()
        store.detailId = "g1"
        store.setTab(.people)
        #expect(store.tab == .people)
        #expect(store.detailId == nil)
    }
}

/// `saveGift` writes through to Core Data and reloads.
@MainActor
struct SaveGiftTests {

    @Test func savingAppendsGiftWithSuggestedValue() {
        let store = makeSeededStore()
        let before = store.gifts.count

        store.add = AddForm()
        store.add.flow = .given
        store.add.name = "Bottle of wine"
        store.add.personId = "igor"
        store.add.memberId = "you"
        store.add.paidByYou = true
        // value left untouched → suggested wine value (1900)
        store.saveGift()

        #expect(store.gifts.count == before + 1)
        let saved = store.gifts.first {
            $0.name == "Bottle of wine" && $0.value == 1900 && $0.flow == .given
        }
        #expect(saved != nil)
        #expect(saved?.emoji == "🍷")
        #expect(saved?.paidByYou == true)
    }

    @Test func touchedValueOverridesSuggestion() {
        let store = makeSeededStore()
        store.add = AddForm()
        store.add.flow = .given
        store.add.name = "Bottle of wine"
        store.add.personId = "igor"
        store.add.valueTouched = true
        store.add.value = 2500
        store.saveGift()

        let saved = store.gifts.first { $0.name == "Bottle of wine" && $0.value == 2500 }
        #expect(saved != nil)
    }

    @Test func receivedGiftIsNeverMarkedPaidByYou() {
        let store = makeSeededStore()
        store.add = AddForm()
        store.add.flow = .received
        store.add.name = "Soft teddy"
        store.add.personId = "maria"
        store.add.paidByYou = true     // should be forced to false for received
        store.saveGift()

        let saved = store.gifts.first { $0.name == "Soft teddy" && $0.flow == .received }
        #expect(saved?.paidByYou == false)
    }
}
