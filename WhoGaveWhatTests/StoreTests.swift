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

/// `canSave` guards the "Add a gift" sheet — direction is now derived from the
/// From → To pickers, so a gift needs a name plus two distinct sides.
@MainActor
struct AddFormTests {

    @Test func requiresNameAndTwoDistinctSides() {
        let store = makeSeededStore()
        #expect(store.canSave() == false)            // blank form

        store.add.name = "Book set"
        #expect(store.canSave() == false)            // no people yet

        store.add.fromId = "igor"
        #expect(store.canSave() == false)            // only the giver chosen

        store.add.toId = "you"
        #expect(store.canSave() == true)             // both sides + name

        store.add.toId = "igor"
        #expect(store.canSave() == false)            // same person on both sides

        store.add.toId = "you"
        store.add.name = "   "
        #expect(store.canSave() == false)            // whitespace-only name
    }

    @Test func directionDerivesFromHouseholdSide() {
        let store = makeSeededStore()
        // Outside person → you: value coming in → Received.
        store.add.fromId = "maria"; store.add.toId = "you"
        #expect(store.addFlow == .received)
        #expect(store.showPaidToggle == false)

        // You → outside person: value going out → Given.
        store.add.fromId = "you"; store.add.toId = "maria"
        #expect(store.addFlow == .given)
        #expect(store.showPaidToggle == false)       // you're the giver, no claim needed

        // A family member (not you) gives → Given, and the "Paid by you" claim applies.
        store.add.fromId = "marina"; store.add.toId = "igor"
        #expect(store.addFlow == .given)
        #expect(store.showPaidToggle == true)
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
        store.add.fromId = "you"        // you gave it → Given
        store.add.toId = "igor"
        store.add.name = "Bottle of wine"
        // value left untouched → suggested wine value (1900)
        store.saveGift()

        #expect(store.gifts.count == before + 1)
        let saved = store.gifts.first {
            $0.name == "Bottle of wine" && $0.value == 1900 && $0.flow == .given
        }
        #expect(saved != nil)
        #expect(saved?.emoji == "🍷")
        #expect(saved?.personId == "igor")     // outside party
        #expect(saved?.memberId == "you")      // household side
        #expect(saved?.paidByYou == true)      // you gave → paid by you by definition
    }

    @Test func touchedValueOverridesSuggestion() {
        let store = makeSeededStore()
        store.add = AddForm()
        store.add.fromId = "you"
        store.add.toId = "igor"
        store.add.name = "Bottle of wine"
        store.add.valueTouched = true
        store.add.value = 2500
        store.saveGift()

        let saved = store.gifts.first { $0.name == "Bottle of wine" && $0.value == 2500 }
        #expect(saved != nil)
    }

    @Test func receivedGiftIsNeverMarkedPaidByYou() {
        let store = makeSeededStore()
        store.add = AddForm()
        store.add.fromId = "maria"      // outside person gave it
        store.add.toId = "you"          // to you → Received
        store.add.name = "Soft teddy"
        store.add.paidByYou = true      // should be forced to false for received
        store.saveGift()

        let saved = store.gifts.first { $0.name == "Soft teddy" && $0.flow == .received }
        #expect(saved?.flow == .received)
        #expect(saved?.paidByYou == false)
    }

    @Test func familyMemberGivenKeepsPaidByYouClaim() {
        let store = makeSeededStore()
        store.add = AddForm()
        store.add.fromId = "marina"     // a family member (not you) gave it
        store.add.toId = "igor"
        store.add.name = "Marina's wine"
        store.add.paidByYou = false     // not paid by the user → stays out of their giving
        store.saveGift()

        let saved = store.gifts.first { $0.name == "Marina's wine" }
        #expect(saved?.flow == .given)
        #expect(saved?.memberId == "marina")
        #expect(saved?.personId == "igor")
        #expect(saved?.paidByYou == false)
    }
}
