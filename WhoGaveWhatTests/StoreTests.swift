import Testing
import Foundation
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

        // You → outside person: value going out → Given.
        store.add.fromId = "you"; store.add.toId = "maria"
        #expect(store.addFlow == .given)

        // A family member (not you) gives → Given.
        store.add.fromId = "marina"; store.add.toId = "igor"
        #expect(store.addFlow == .given)
    }

    @Test func paidToggleIsAlwaysOffered() {
        let store = makeSeededStore()
        // Regardless of direction, the user may have footed the bill themselves.
        store.add.fromId = "maria"; store.add.toId = "you"   // received
        #expect(store.showPaidToggle == true)
        store.add.fromId = "you"; store.add.toId = "maria"   // given by you
        #expect(store.showPaidToggle == true)
        store.add.fromId = "marina"; store.add.toId = "igor" // given by family
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

    @Test func receivedGiftCanBeMarkedPaidByYou() {
        let store = makeSeededStore()
        store.add = AddForm()
        store.add.fromId = "maria"      // outside person gave it
        store.add.toId = "you"          // to you → Received
        store.add.name = "Soft teddy"
        store.add.paidByYou = true      // the user footed the bill themselves
        store.saveGift()

        // "Paid by you" is honoured in any direction now (it's always offered).
        let saved = store.gifts.first { $0.name == "Soft teddy" && $0.flow == .received }
        #expect(saved?.flow == .received)
        #expect(saved?.paidByYou == true)
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

/// Timeline ordering: newest day first, then by creation time within a day.
@MainActor
struct OrderingTests {

    private func gift(_ id: String, date: Date) -> Gift {
        Gift(id: id, emoji: "🎁", name: id, flow: .received, personId: "p",
             memberId: "you", paidByYou: false, celebration: "", date: date, value: 0)
    }

    @Test func creationSeqParsesTheIdSuffix() {
        #expect(gift("g12", date: AppStore.today).creationSeq == 12)
        #expect(gift("g1750000000000", date: AppStore.today).creationSeq == 1_750_000_000_000)
    }

    @Test func sameDayOrdersByCreationDescending() {
        let earlier = gift("g1000", date: AppStore.today)
        let later = gift("g2000", date: AppStore.today)
        // Created later that same day → sorts above the earlier one.
        #expect(Gift.newestFirst(later, earlier) == true)
        #expect(Gift.newestFirst(earlier, later) == false)
    }

    @Test func newerDayBeatsCreationSeq() {
        // Even with a much larger creation seq, an older day stays below.
        let oldDayBigSeq = gift("g9999999999999", date: AppStore.yesterday)
        let newDaySmallSeq = gift("g1", date: AppStore.today)
        #expect(Gift.newestFirst(newDaySmallSeq, oldDayBigSeq) == true)
    }
}

/// The gift row subtitle reads "giver → receiver" in both directions.
@MainActor
struct SubtitleTests {

    @Test func subtitleIsAlwaysGiverArrowReceiver() {
        let store = makeSeededStore()

        // Received seed: outside person → household member.
        let recv = store.gifts.first { $0.id == "g1" }!
        #expect(store.giftSubtitle(recv) ==
                "\(store.personName(recv.personId))  →  \(store.memberName(recv.memberId))")

        // Given seed: household member → outside person (no "to"/"·" decoration).
        let given = store.gifts.first { $0.id == "g8" }!
        #expect(store.giftSubtitle(given) ==
                "\(store.memberName(given.memberId))  →  \(store.personName(given.personId))")
        #expect(!store.giftSubtitle(given).contains("·"))
    }
}
