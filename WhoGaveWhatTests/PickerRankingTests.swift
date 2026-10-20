import Foundation
import Testing

@testable import WhoGaveWhat

private let origin = Date(timeIntervalSince1970: 1_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    origin.addingTimeInterval(seconds)
}

private func makeRankedGift(
    _ id: String,
    from giverID: String,
    to recipientID: String,
    occasion: String = "Just because",
    date: Date = at(0),
    createdAt: Date,
    lastSavedAt: Date? = nil
) -> Gift {
    Gift(
        id: id, emoji: "🎁", name: id, giverID: giverID, recipientID: recipientID,
        paidByYou: false, occasion: occasion, date: date, value: 0,
        createdAt: createdAt, lastSavedAt: lastSavedAt)
}

private let allPeople = [
    Person(id: "alex", name: "Alex", colorHex: 0x123456),
    Person(id: "alice", name: "Alice", colorHex: 0x654321),
    Person(id: "bob", name: "Bob", colorHex: 0xABCDEF),
    Person(id: "carol", name: "Carol", colorHex: 0xFEDCBA)
]

struct RankPickerPeopleTests {
    private let useCase = RankPickerOptionsUseCase()

    private func ids(_ role: PersonPickerRole, _ gifts: [Gift]) -> [String] {
        useCase.rankPeople(allPeople, by: role, in: gifts).map(\.id)
    }

    @Test func withoutGiftsKeepsTheGivenOrder() {
        #expect(ids(.giver, []) == ["alex", "alice", "bob", "carol"])
        #expect(ids(.recipient, []) == ["alex", "alice", "bob", "carol"])
    }

    @Test func rolesAreRankedIndependently() {
        let gifts = [makeRankedGift("g1", from: "bob", to: "carol", createdAt: at(10))]

        #expect(ids(.giver, gifts) == ["bob", "alex", "alice", "carol"])
        #expect(ids(.recipient, gifts) == ["carol", "alex", "alice", "bob"])
    }

    @Test func mostRecentUseComesFirst() {
        let gifts = [
            makeRankedGift("old", from: "alice", to: "alex", createdAt: at(10)),
            makeRankedGift("new", from: "carol", to: "alex", createdAt: at(20)),
            makeRankedGift("mid", from: "bob", to: "alex", createdAt: at(15))
        ]

        #expect(ids(.giver, gifts) == ["carol", "bob", "alice", "alex"])
    }

    @Test func editedOlderGiftJumpsToTheTop() {
        let gifts = [
            makeRankedGift("edited", from: "alice", to: "alex", createdAt: at(10), lastSavedAt: at(100)),
            makeRankedGift("newer", from: "bob", to: "alex", createdAt: at(50))
        ]

        #expect(ids(.giver, gifts) == ["alice", "bob", "alex", "carol"])
    }

    @Test func fallsBackToCreationTimeWithoutALastSavedTime() {
        let gifts = [
            makeRankedGift("a", from: "alice", to: "alex", createdAt: at(10)),
            makeRankedGift("b", from: "bob", to: "alex", createdAt: at(5), lastSavedAt: at(8))
        ]

        #expect(gifts[0].lastUsedAt == at(10))
        #expect(gifts[1].lastUsedAt == at(8))
        #expect(ids(.giver, gifts) == ["alice", "bob", "alex", "carol"])
    }

    @Test func aBackdatedGiftDateDoesNotAffectRecency() {
        let gifts = [
            makeRankedGift("backdated", from: "alice", to: "alex", date: at(-1_000_000), createdAt: at(20)),
            makeRankedGift("future", from: "bob", to: "alex", date: at(1_000_000), createdAt: at(10))
        ]

        #expect(ids(.giver, gifts) == ["alice", "bob", "alex", "carol"])
    }

    @Test func theLatestUseOfAPersonCounts() {
        let gifts = [
            makeRankedGift("a1", from: "alice", to: "alex", createdAt: at(1)),
            makeRankedGift("b1", from: "bob", to: "alex", createdAt: at(5)),
            makeRankedGift("a2", from: "alice", to: "alex", createdAt: at(9))
        ]

        #expect(ids(.giver, gifts) == ["alice", "bob", "alex", "carol"])
    }

    @Test func frequencyBreaksTiesBetweenEqualTimes() {
        let gifts = [
            makeRankedGift("a1", from: "alice", to: "alex", createdAt: at(10)),
            makeRankedGift("b1", from: "bob", to: "alex", createdAt: at(1)),
            makeRankedGift("b2", from: "bob", to: "alex", createdAt: at(10))
        ]

        #expect(ids(.giver, gifts) == ["bob", "alice", "alex", "carol"])
    }

    @Test func originalOrderBreaksTiesOfTimeAndFrequency() {
        let gifts = [
            makeRankedGift("c1", from: "carol", to: "alex", createdAt: at(10)),
            makeRankedGift("b1", from: "bob", to: "alex", createdAt: at(10))
        ]

        #expect(ids(.giver, gifts) == ["bob", "carol", "alex", "alice"])
    }

    @Test func neverUsedPeopleKeepTheirOrderBelowRankedOnes() {
        let gifts = [makeRankedGift("g", from: "carol", to: "bob", createdAt: at(10))]

        #expect(ids(.giver, gifts) == ["carol", "alex", "alice", "bob"])
        #expect(ids(.recipient, gifts) == ["bob", "alex", "alice", "carol"])
    }

    @Test func peopleMissingFromTheListAreIgnored() {
        let gifts = [
            makeRankedGift("g1", from: "ghost", to: "bob", createdAt: at(20)),
            makeRankedGift("g2", from: "alice", to: "ghost", createdAt: at(10))
        ]

        #expect(ids(.giver, gifts) == ["alice", "alex", "bob", "carol"])
        #expect(ids(.recipient, gifts) == ["bob", "alex", "alice", "carol"])
    }

    @Test func removingAGiftRemovesItsContribution() {
        let kept = makeRankedGift("kept", from: "alice", to: "alex", createdAt: at(10))
        let deleted = makeRankedGift("deleted", from: "bob", to: "alex", createdAt: at(20))

        #expect(ids(.giver, [kept, deleted]) == ["bob", "alice", "alex", "carol"])
        #expect(ids(.giver, [kept]) == ["alice", "alex", "bob", "carol"])
    }
}

@MainActor
struct RankPickerOccasionTests {
    private let useCase = RankPickerOptionsUseCase()
    private let occasions = AppData.defaultOccasions

    private func names(_ gifts: [Gift]) -> [String] {
        useCase.rankOccasions(occasions, in: gifts).map(\.name)
    }

    @Test func withoutGiftsKeepsTheDefaultOrder() {
        #expect(names([]) == occasions.map(\.name))
    }

    @Test func rankedByRecencyThenFrequencyWithDefaultOrderBelow() {
        let gifts = [
            makeRankedGift("a", from: "alex", to: "bob", occasion: "Wedding", createdAt: at(10)),
            makeRankedGift("b", from: "alex", to: "bob", occasion: "Graduation", createdAt: at(30)),
            makeRankedGift("c", from: "alex", to: "bob", occasion: "Birthday", createdAt: at(10)),
            makeRankedGift("d", from: "alex", to: "bob", occasion: "Birthday", createdAt: at(10))
        ]

        #expect(
            names(gifts) == [
                "Graduation", "Birthday", "Wedding", "New Year", "Anniversary", "Housewarming", "Just because"
            ])
    }

    @Test func editedGiftMovesItsOccasionToTheTop() {
        let gifts = [
            makeRankedGift("a", from: "alex", to: "bob", occasion: "Wedding", createdAt: at(10), lastSavedAt: at(99)),
            makeRankedGift("b", from: "alex", to: "bob", occasion: "Birthday", createdAt: at(50))
        ]

        #expect(Array(names(gifts).prefix(2)) == ["Wedding", "Birthday"])
    }

    @Test func emptyAndUnknownOccasionNamesAreIgnored() {
        let gifts = [
            makeRankedGift("a", from: "alex", to: "bob", occasion: "", createdAt: at(30)),
            makeRankedGift("b", from: "alex", to: "bob", occasion: "Name day", createdAt: at(20)),
            makeRankedGift("c", from: "alex", to: "bob", occasion: "wedding", createdAt: at(10))
        ]

        #expect(names(gifts) == occasions.map(\.name))
    }

    @Test func customSavedOccasionsAreRankedToo() {
        let custom = occasions + [Occasion(name: "Name day")]
        let gifts = [makeRankedGift("a", from: "alex", to: "bob", occasion: "Name day", createdAt: at(10))]

        #expect(useCase.rankOccasions(custom, in: gifts).first?.name == "Name day")
    }

    @Test func removingAGiftRemovesItsContribution() {
        let gift = makeRankedGift("a", from: "alex", to: "bob", occasion: "Wedding", createdAt: at(10))

        #expect(names([gift]).first == "Wedding")
        #expect(names([]).first == "Birthday")
    }
}

@MainActor
struct PickerRankingCompositionTests {
    @Test func seededHistoryRanksEachRoleByRecentUse() throws {
        let composition = try makeTestComposition()

        #expect(
            composition.rankedPeople(for: .giver).map(\.id) == [
                "sofia", "anton", "olga", "maria", "pavel", "igor", "dmitri", "marina", "alisa", "lena"
            ])
        #expect(composition.rankedPeople(for: .recipient).first?.id == "lena")
        #expect(composition.rankedOccasions.first?.name == "Birthday")
    }

    @Test func savingAGiftPromotesItsPeopleAndOccasionOnlyInTheirRoles() throws {
        let composition = try makeTestComposition()
        var input = makeGiftInput(name: "Cake", fromID: "dmitri", toID: "igor")
        input.occasion = "Wedding"

        composition.saveGift(input)

        let givers = composition.rankedPeople(for: .giver).map(\.id)
        let recipients = composition.rankedPeople(for: .recipient).map(\.id)
        #expect(givers.first == "dmitri")
        #expect(recipients.first == "igor")
        #expect(givers.firstIndex(of: "igor") != 0)
        #expect(recipients.firstIndex(of: "dmitri") != 0)
        #expect(composition.rankedOccasions.first?.name == "Wedding")
    }

    @Test func editingAnOldGiftPromotesItButKeepsItsCreationTime() throws {
        let composition = try makeTestComposition()
        let original = try #require(composition.data.gifts.first { $0.id == "g5" })
        var input = makeGiftInput(name: "Edited wine", fromID: "dmitri", toID: "anton")
        input.editingGiftID = original.id
        input.createdAt = original.createdAt

        composition.saveGift(input)

        let edited = try #require(composition.data.gifts.first { $0.id == "g5" })
        #expect(edited.createdAt == original.createdAt)
        #expect(edited.lastSavedAt != nil)
        #expect(composition.rankedPeople(for: .giver).first?.id == "dmitri")
    }

    @Test func deletingAGiftRemovesItsContribution() throws {
        let composition = try makeTestComposition()

        composition.deleteGift(id: "g8")

        #expect(
            composition.rankedPeople(for: .giver).map(\.id) == [
                "anton", "olga", "maria", "pavel", "igor", "dmitri", "marina", "sofia", "alisa", "lena"
            ])
    }
}

@MainActor
struct PickerRankingSaveGiftTests {
    @Test func newGiftIsStampedWithTheClock() throws {
        let stamp = at(500)
        let (useCase, gateway) = makeSaveGiftUseCase(now: { stamp })

        let saved = try useCase.execute(makeGiftInput(name: "Book", fromID: "you", toID: "igor"))

        #expect(saved?.lastSavedAt == stamp)
        #expect(saved?.createdAt == stamp)
        #expect(gateway.gifts.first?.lastSavedAt == stamp)
    }

    @Test func editingStampsLastSavedAtAndKeepsCreationTime() throws {
        let createdAt = at(100)
        var clock = at(500)
        let (useCase, gateway) = makeSaveGiftUseCase(now: { clock })
        var input = makeGiftInput(name: "Book", fromID: "you", toID: "igor")
        input.editingGiftID = "existing-id"
        input.createdAt = createdAt

        try useCase.execute(input)
        clock = at(900)
        try useCase.execute(input)

        #expect(gateway.gifts.count == 1)
        #expect(gateway.gifts.first?.createdAt == createdAt)
        #expect(gateway.gifts.first?.lastSavedAt == at(900))
        #expect(gateway.gifts.first?.lastUsedAt == at(900))
    }
}

@MainActor
struct PickerRankingPersonPickerStateTests {
    private let people = allPeople

    @Test func keepsAnExistingSelectionExactly() {
        let state = PersonPickerState(people: people, selectedID: "bob", counterpartID: "alex")
        let sameAsCounterpart = PersonPickerState(people: people, selectedID: "alex", counterpartID: "alex")

        #expect(state.selectedID == "bob")
        #expect(sameAsCounterpart.selectedID == "alex")
    }

    @Test func preselectsTheFirstRankedPersonWithoutASelection() {
        let ranked = RankPickerOptionsUseCase().rankPeople(
            people, by: .giver,
            in: [makeRankedGift("g", from: "carol", to: "alex", createdAt: at(10))])

        let state = PersonPickerState(people: ranked, selectedID: nil)

        #expect(state.selectedID == "carol")
    }

    @Test func preselectionSkipsTheCounterpart() {
        let state = PersonPickerState(people: people, selectedID: nil, counterpartID: "alex")
        let onlyCounterpart = PersonPickerState(people: [people[0]], selectedID: nil, counterpartID: "alex")

        #expect(state.selectedID == "alice")
        #expect(state.visiblePeople.map(\.id).contains("alex"))
        #expect(onlyCounterpart.selectedID == nil)
    }

    @Test func queryPreselectionSkipsTheCounterpartButKeepsItVisible() {
        let state = PersonPickerState(people: people, selectedID: "bob", counterpartID: "alex")

        let selection = state.updateQuery("Al")

        #expect(state.visiblePeople.map(\.id) == ["alex", "alice"])
        #expect(selection == "alice")
        #expect(state.selectedID == "alice")
    }

    @Test func filteringKeepsTheRankedOrder() {
        let ranked = [people[2], people[1], people[0], people[3]]
        let state = PersonPickerState(people: ranked, selectedID: nil)

        let selection = state.updateQuery("Al")

        #expect(state.visiblePeople.map(\.id) == ["alice", "alex"])
        #expect(selection == "alice")
        _ = state.updateQuery("")
        #expect(state.visiblePeople.map(\.id) == ["bob", "alice", "alex", "carol"])
    }
}
