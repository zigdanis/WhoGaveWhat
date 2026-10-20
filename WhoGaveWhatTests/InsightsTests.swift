import Foundation
import Testing

@testable import WhoGaveWhat

struct InsightsTests {
    private let calendar = Calendar.current
    private let useCase = BuildInsightsUseCase()
    private let now = Date()
    private var year: Int { calendar.component(.year, from: now) }

    private let me = Person(id: "me", name: "Me", colorHex: 0x112233)
    private let alice = Person(id: "alice", name: "Alice", colorHex: 0x223344)
    private let bob = Person(id: "bob", name: "Bob", colorHex: 0x334455)
    private let carol = Person(id: "carol", name: "Carol", colorHex: 0x445566)
    private let dave = Person(id: "dave", name: "Dave", colorHex: 0x556677)
    private var people: [Person] { [me, bob, carol, alice] }

    private func gift(_ id: String, from giver: Person, to recipient: Person, _ value: Double, year: Int) -> Gift {
        let date = calendar.date(from: DateComponents(year: year, month: 6, day: 15, hour: 12))!
        return Gift(
            id: id, emoji: "🎁", name: id, giverID: giver.id, recipientID: recipient.id,
            paidByYou: false, occasion: "", date: date, value: value, createdAt: date)
    }

    private var gifts: [Gift] {
        [
            gift("a-to-me", from: alice, to: me, 100, year: year),
            gift("me-to-a", from: me, to: alice, 40, year: year),
            gift("b-to-me", from: bob, to: me, 30, year: year),
            gift("me-to-b", from: me, to: bob, 90, year: year),
            gift("c-to-me-old", from: carol, to: me, 500, year: year - 1),
            gift("a-to-b", from: alice, to: bob, 999, year: year)
        ]
    }

    // MARK: Years

    @Test func availableYearsAreDistinctAndNewestFirst() {
        #expect(useCase.availableYears(gifts: gifts) == [year, year - 1])
        #expect(useCase.availableYears(gifts: []).isEmpty)
    }

    @Test func resolvedYearPrefersASelectionThatStillHasGifts() {
        #expect(useCase.resolvedYear(selected: year - 1, gifts: gifts, now: now) == year - 1)
        #expect(useCase.resolvedYear(selected: year + 5, gifts: gifts, now: now) == year)
        #expect(useCase.resolvedYear(selected: nil, gifts: gifts, now: now) == year)
    }

    @Test func resolvedYearFallsBackToTheLatestYearWithGifts() {
        let older = gifts.filter { calendar.component(.year, from: $0.date) == year - 1 }
        #expect(useCase.resolvedYear(selected: nil, gifts: older, now: now) == year - 1)
    }

    @Test func resolvedYearWithoutGiftsIsTheCurrentYear() {
        #expect(useCase.resolvedYear(selected: nil, gifts: [], now: now) == year)
        #expect(useCase.resolvedYear(selected: year - 2, gifts: [], now: now) == year)
    }

    @Test func giftsAreFilteredByYear() {
        #expect(useCase.gifts(gifts, in: year).count == 5)
        #expect(useCase.gifts(gifts, in: year - 1).map(\.id) == ["c-to-me-old"])
        #expect(useCase.gifts(gifts, in: nil).count == 6)
    }

    // MARK: Summary

    @Test func summarySplitsRelativeToTheViewpoint() {
        let summary = useCase.summary(gifts: gifts, relativeTo: me.id, year: year)
        #expect(summary.circulatedValue == 100 + 40 + 30 + 90 + 999)
        #expect(summary.giftCount == 5)
        #expect(summary.receivedValue == 130)
        #expect(summary.receivedCount == 2)
        #expect(summary.givenValue == 130)
        #expect(summary.givenCount == 2)
        #expect(summary.net == 0)
        #expect(summary.isEven)
    }

    @Test func summaryWithoutViewpointOnlyCirculates() {
        let summary = useCase.summary(gifts: gifts, relativeTo: nil, year: year)
        #expect(summary.circulatedValue == 1_259)
        #expect(summary.receivedCount == 0)
        #expect(summary.givenCount == 0)
    }

    // MARK: Balances

    @Test func balancesListEveryoneTheViewpointExchangedWith() {
        let balances = useCase.balances(gifts: gifts, people: people, relativeTo: me.id, year: year)
        #expect(balances.map(\.person.id) == ["alice", "bob"])
        #expect(balances[0].receivedValue == 100)
        #expect(balances[0].givenValue == 40)
        #expect(balances[0].net == 60)
        #expect(balances[1].net == -60)
        #expect(balances[0].receivedCount == 1)
        #expect(balances[0].givenCount == 1)
    }

    @Test func balancesSortByAbsoluteNetThenName() {
        let allYears = useCase.balances(gifts: gifts, people: people, relativeTo: me.id, year: nil)
        #expect(allYears.map(\.person.id) == ["carol", "alice", "bob"])
        #expect(allYears.first?.net == 500)
    }

    @Test func countBalanceIsPositiveWhenTheViewpointReceivedMoreGifts() {
        let received = [
            gift("a1", from: alice, to: me, 10, year: year),
            gift("a2", from: alice, to: me, 10, year: year),
            gift("a3", from: me, to: alice, 10, year: year)
        ]
        let balance = useCase.balances(gifts: received, people: people, relativeTo: me.id, year: year)[0]
        #expect(balance.countNet == 1)
        #expect(balance.isCountEven == false)
        // Seen from Alice's side, the same exchange flips the sign.
        let fromAlice = useCase.balances(gifts: received, people: people, relativeTo: alice.id, year: year)[0]
        #expect(fromAlice.countNet == -1)
    }

    @Test func countBalanceIsNegativeWhenTheViewpointGaveMoreGifts() {
        let given = [
            gift("b1", from: me, to: bob, 10, year: year),
            gift("b2", from: me, to: bob, 10, year: year),
            gift("b3", from: me, to: bob, 10, year: year),
            gift("b4", from: bob, to: me, 10, year: year)
        ]
        let balance = useCase.balances(gifts: given, people: people, relativeTo: me.id, year: year)[0]
        #expect(balance.countNet == -2)
        #expect(balance.isCountEven == false)
    }

    @Test func countBalanceIsEvenForEqualCountsEvenWhenMoneyDiffers() {
        let balance = useCase.balances(gifts: gifts, people: people, relativeTo: me.id, year: year)[0]
        #expect(balance.receivedCount == balance.givenCount)
        #expect(balance.countNet == 0)
        #expect(balance.isCountEven)
        #expect(balance.net != 0)
    }

    @Test func balancesSortByAbsoluteCountBalanceThenMoneyThenName() {
        let mixed = [
            // Alice: even count, large money gap.
            gift("a-in", from: alice, to: me, 1_000, year: year),
            gift("a-out", from: me, to: alice, 2_500, year: year),
            // Bob: two gifts given, tiny money.
            gift("b-out-1", from: me, to: bob, 5, year: year),
            gift("b-out-2", from: me, to: bob, 5, year: year),
            // Carol: one gift received, big money.
            gift("c-in", from: carol, to: me, 9_000, year: year),
            // Dave: one gift given, small money; ties with Carol on count, loses on money.
            gift("d-out", from: me, to: dave, 50, year: year)
        ]
        let balances = useCase.balances(gifts: mixed, people: people + [dave], relativeTo: me.id, year: year)
        #expect(balances.map(\.person.id) == ["bob", "carol", "dave", "alice"])
        #expect(balances.map(\.countNet) == [-2, 1, -1, 0])
    }

    @Test func balancesWithEqualCountAndMoneySortByName() {
        let tied = [
            gift("b-in", from: bob, to: me, 10, year: year),
            gift("a-in", from: alice, to: me, 10, year: year)
        ]
        let balances = useCase.balances(gifts: tied, people: people, relativeTo: me.id, year: year)
        #expect(balances.map(\.person.id) == ["alice", "bob"])
    }

    @Test func balancesExcludeTheViewpointAndGiftsBetweenOthers() {
        let balances = useCase.balances(gifts: gifts, people: people, relativeTo: alice.id, year: year)
        // Alice also gave to Bob, which only Alice's own view counts.
        #expect(balances.map(\.person.id) == ["bob", "me"])
        #expect(balances.first?.net == -999)
        #expect(balances.contains { $0.person.id == alice.id } == false)
    }

    @Test func balancesAreEmptyWithoutSharedGifts() {
        #expect(useCase.balances(gifts: [], people: people, relativeTo: me.id, year: year).isEmpty)
        #expect(useCase.balances(gifts: gifts, people: people, relativeTo: carol.id, year: year).isEmpty)
        #expect(useCase.balances(gifts: gifts, people: [me], relativeTo: me.id, year: nil).isEmpty)
    }

    // MARK: Comparison

    @Test func comparisonTotalsBothDirections() {
        let result = useCase.comparison(gifts: gifts, a: me, b: alice, year: year)
        #expect(result.aToBValue == 40)
        #expect(result.aToBCount == 1)
        #expect(result.bToAValue == 100)
        #expect(result.bToACount == 1)
        #expect(result.net == 60)
        #expect(!result.isEven)
    }

    @Test func comparisonIsSymmetric() {
        let forward = useCase.comparison(gifts: gifts, a: alice, b: bob, year: nil)
        let backward = useCase.comparison(gifts: gifts, a: bob, b: alice, year: nil)
        #expect(forward.aToBValue == backward.bToAValue)
        #expect(forward.aToBCount == backward.bToACount)
        #expect(forward.bToAValue == backward.aToBValue)
        #expect(forward.net == -backward.net)
        #expect(forward.aToBValue == 999)
    }

    @Test func comparisonRespectsTheYearAndIgnoresOtherPeople() {
        #expect(useCase.comparison(gifts: gifts, a: me, b: carol, year: year).bToAValue == 0)
        #expect(useCase.comparison(gifts: gifts, a: me, b: carol, year: year - 1).bToAValue == 500)
        #expect(useCase.comparison(gifts: gifts, a: bob, b: carol, year: nil).aToBCount == 0)
    }

    @Test func comparisonWithoutGiftsIsEven() {
        let result = useCase.comparison(gifts: [], a: me, b: alice, year: year)
        #expect(result.aToBValue == 0)
        #expect(result.bToAValue == 0)
        #expect(result.aToBCount == 0)
        #expect(result.bToACount == 0)
        #expect(result.isEven)
    }

    // MARK: Defaults

    @Test func focusPersonIsTheViewpointOtherwiseFirstAlphabetically() {
        #expect(useCase.focusPerson(people: people, selfPersonID: bob.id)?.id == "bob")
        #expect(useCase.focusPerson(people: people, selfPersonID: nil)?.id == "alice")
        #expect(useCase.focusPerson(people: people, selfPersonID: "missing")?.id == "alice")
        #expect(useCase.focusPerson(people: [], selfPersonID: nil) == nil)
    }

    @Test func defaultCounterpartIsTheLargestBalanceOrFirstOtherPerson() {
        #expect(useCase.defaultCounterpart(gifts: gifts, people: people, for: me, year: nil)?.id == "carol")
        #expect(useCase.defaultCounterpart(gifts: gifts, people: people, for: me, year: year)?.id == "alice")
        #expect(useCase.defaultCounterpart(gifts: [], people: people, for: alice, year: year)?.id == "bob")
        #expect(useCase.defaultCounterpart(gifts: [], people: [alice], for: alice, year: year) == nil)
    }
}
