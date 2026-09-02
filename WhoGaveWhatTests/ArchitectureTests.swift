import Foundation
import Testing
@testable import WhoGaveWhat

@MainActor
struct SeededDataTests {
    @Test func loadsTheSampleDatasetThroughGateways() {
        let composition = makeTestComposition()
        #expect(composition.data.gifts.count == 12)
        #expect(composition.data.householdMembers.count == 4)
        #expect(composition.data.contacts.count == 6)
        #expect(composition.data.people.count == 10)
    }

    @Test func insightsSplitAndSumGifts() {
        let composition = makeTestComposition()
        let insights = composition.buildInsights.execute(
            gifts: composition.data.gifts,
            people: composition.data.contacts
        )
        #expect(insights.received.count == 7)
        #expect(insights.given.count == 5)
        #expect(insights.receivedValue == 19_300)
        #expect(insights.givenValue == 11_800)
        #expect([Gift]().totalValue == 0)
    }
}

@MainActor
struct SaveGiftInputTests {
    @Test func requiresNameAndTwoDistinctSides() {
        #expect(!makeGiftInput().canSave)
        #expect(!makeGiftInput(name: "Book set").canSave)
        #expect(!makeGiftInput(name: "Book set", fromID: "igor").canSave)
        #expect(makeGiftInput(name: "Book set", fromID: "igor", toID: "you").canSave)
        #expect(!makeGiftInput(name: "Book set", fromID: "igor", toID: "igor").canSave)
        #expect(!makeGiftInput(name: "   ", fromID: "igor", toID: "you").canSave)
    }

    @Test func directionDerivesFromHouseholdSide() {
        let composition = makeTestComposition()
        let ids = composition.data.householdIDs
        let useCase = composition.saveGiftUseCase
        #expect(useCase.direction(for: makeGiftInput(fromID: "maria", toID: "you"), householdIDs: ids) == .received)
        #expect(useCase.direction(for: makeGiftInput(fromID: "you", toID: "maria"), householdIDs: ids) == .given)
        #expect(useCase.direction(for: makeGiftInput(fromID: "marina", toID: "igor"), householdIDs: ids) == .given)
    }

    @Test func directionFallsBackToReceivedForSameSideEndpoints() {
        let useCase = makeSaveGiftUseCase().0
        let householdIDs: Set<String> = ["you", "marina", "sofia"]

        #expect(useCase.direction(for: makeGiftInput(fromID: "marina", toID: "sofia"), householdIDs: householdIDs) == .received)
        #expect(useCase.direction(for: makeGiftInput(fromID: "maria", toID: "igor"), householdIDs: householdIDs) == .received)
    }

    @Test func directionDoesNotSpecialCaseLegacySelfID() {
        let useCase = makeSaveGiftUseCase().0

        #expect(useCase.direction(for: makeGiftInput(fromID: "you", toID: "marina"), householdIDs: ["you", "marina"]) == .received)
        #expect(useCase.direction(for: makeGiftInput(fromID: "marina", toID: "you"), householdIDs: ["you", "marina"]) == .received)
        #expect(useCase.direction(for: makeGiftInput(fromID: "you", toID: "maria"), householdIDs: []) == .received)
        #expect(useCase.direction(for: makeGiftInput(fromID: "maria", toID: "you"), householdIDs: []) == .received)
    }
}

struct GiftDirectionResolverTests {
    @Test func resolvesYouToAliceFromBothEndpoints() {
        #expect(GiftDirectionResolver.resolve(giverID: "you", recipientID: "alice", relativeTo: "you") == .given)
        #expect(GiftDirectionResolver.resolve(giverID: "you", recipientID: "alice", relativeTo: "alice") == .received)
    }

    @Test func resolvesContactToContactFromBothEndpoints() {
        #expect(GiftDirectionResolver.resolve(giverID: "contact-a", recipientID: "contact-b", relativeTo: "contact-a") == .given)
        #expect(GiftDirectionResolver.resolve(giverID: "contact-a", recipientID: "contact-b", relativeTo: "contact-b") == .received)
    }

    @Test func returnsNilForNonEndpoint() {
        #expect(GiftDirectionResolver.resolve(giverID: "contact-a", recipientID: "contact-b", relativeTo: "observer") == nil)
    }
}

@MainActor
struct AddGiftDraftTests {
    @Test func newGiftStartsWithSimpleDefaults() {
        let draft = AddGiftDraft()
        #expect(draft.fromID == nil)
        #expect(draft.toID == nil)
        #expect(draft.occasion == "Just because")
        #expect(draft.date == AppDate.today)
        #expect(!draft.valueTouched)
    }
}

@MainActor
struct PersonPickerStateTests {
    private let people = [
        Person(id: "alex", name: "Alex", colorHex: 0x123456, role: .contact),
        Person(id: "alice", name: "Alice", colorHex: 0x654321, role: .household),
        Person(id: "bob", name: "Bob", colorHex: 0xABCDEF, role: .contact),
    ]

    @Test func filtersAndProvisionallySelectsTheFirstMatch() {
        let state = PersonPickerState(people: people, selectedID: "bob")

        let selection = state.updateQuery("Al")

        #expect(state.visiblePeople.map(\.id) == ["alex", "alice"])
        #expect(selection == "alex")
        #expect(state.selectedID == "alex")
    }

    @Test func preservesSelectionWhenAQueryHasNoMatches() {
        let state = PersonPickerState(people: people, selectedID: "bob")

        let selection = state.updateQuery("New person")

        #expect(state.visiblePeople.isEmpty)
        #expect(selection == nil)
        #expect(state.selectedID == "bob")
    }

    @Test func clearingQueryRestoresAllPeopleWithoutChangingSelection() {
        let state = PersonPickerState(people: people, selectedID: nil)
        _ = state.updateQuery("Ali")

        let selection = state.updateQuery("")

        #expect(state.visiblePeople.map(\.id) == people.map(\.id))
        #expect(selection == nil)
        #expect(state.selectedID == "alice")
    }
}

@MainActor
struct RouterTests {
    @Test func routesScreensTabsAndSheetsIndependently() {
        let router = AppRouter(didCompleteOnboarding: false, launchEnvironment: [:])
        #expect(router.screen == .onboarding)
        router.showSignIn()
        #expect(router.screen == .signIn)
        router.showMainApp()
        router.selectTab(.people)
        router.presentEditGift(id: "g1")
        #expect(router.screen == .main)
        #expect(router.tab == .people)
        #expect(router.giftSheet == .edit(giftID: "g1"))
        router.dismissGiftSheet()
        #expect(router.giftSheet == nil)
    }
}

@MainActor
struct SaveGiftTests {
    @Test func savingUsesSuggestedValueAndReloadsData() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(
            makeGiftInput(name: "Bottle of wine", fromID: "you", toID: "igor"),
            householdIDs: ["you", "marina"]
        )
        let saved = gateway.gifts.first { $0.name == "Bottle of wine" }
        #expect(saved?.value == 1_900)
        #expect(saved?.emoji == "🍷")
        #expect(saved?.direction == .given)
        #expect(saved?.giverID == "you")
        #expect(saved?.recipientID == "igor")
        #expect(saved?.paidByYou == false)
    }

    @Test func touchedValueOverridesSuggestion() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(makeGiftInput(
            name: "Bottle of wine", fromID: "you", toID: "igor", value: 2_500,
            valueTouched: true), householdIDs: ["you"])
        #expect(gateway.gifts.contains { $0.name == "Bottle of wine" && $0.value == 2_500 })
    }

    @Test func receivedGiftCanBeMarkedPaidByYou() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(makeGiftInput(
            name: "Soft teddy", fromID: "maria", toID: "you", paidByYou: true
        ), householdIDs: ["you"])
        let saved = gateway.gifts.first { $0.name == "Soft teddy" }
        #expect(saved?.direction == .received)
        #expect(saved?.paidByYou == true)
    }

    @Test func familyMemberGiftKeepsPaidByYouFalse() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(makeGiftInput(
            name: "Marina's wine", fromID: "marina", toID: "igor"
        ), householdIDs: ["you", "marina"])
        let saved = gateway.gifts.first { $0.name == "Marina's wine" }
        #expect(saved?.direction == .given)
        #expect(saved?.giverID == "marina")
        #expect(saved?.recipientID == "igor")
        #expect(saved?.paidByYou == false)
    }

    @Test func editingPreservesStableIDAndCreationTime() throws {
        let (useCase, gateway) = makeSaveGiftUseCase()
        let createdAt = Date(timeIntervalSince1970: 123)
        var input = makeGiftInput(name: "Edited gift", fromID: "you", toID: "igor")
        input.editingGiftID = "existing-id"
        input.createdAt = createdAt

        try useCase.execute(input, householdIDs: ["you"])

        #expect(gateway.gifts.first?.id == "existing-id")
        #expect(gateway.gifts.first?.createdAt == createdAt)
    }
}

struct OrderingTests {
    private func gift(_ id: String, date: Date, createdAt: Date) -> Gift {
        Gift(id: id, emoji: "🎁", name: id, direction: .received, giverID: "p",
             recipientID: "you", paidByYou: false, occasion: "", date: date, value: 0,
             createdAt: createdAt)
    }

    @Test func sameDayOrdersByCreationDescending() {
        let earlier = gift("arbitrary-newer-id", date: AppDate.today, createdAt: AppDate.yesterday)
        let later = gift("arbitrary-older-id", date: AppDate.today, createdAt: AppDate.today)
        #expect(Gift.newestFirst(later, earlier))
        #expect(!Gift.newestFirst(earlier, later))
    }

    @Test func newerGiftDateBeatsCreationTime() {
        let oldDay = gift("old", date: AppDate.yesterday, createdAt: AppDate.today)
        let newDay = gift("new", date: AppDate.today, createdAt: AppDate.yesterday)
        #expect(Gift.newestFirst(newDay, oldDay))
    }
}

@MainActor
struct SubtitleTests {
    @Test func subtitleIsAlwaysGiverArrowReceiver() {
        let composition = makeTestComposition()
        let data = composition.data
        let received = data.gifts.first { $0.id == "g1" }!
        #expect(data.giftSubtitle(received) ==
                "\(data.entityName(received.giverID))  →  \(data.entityName(received.recipientID))")
        let given = data.gifts.first { $0.id == "g8" }!
        #expect(data.giftSubtitle(given) ==
                "\(data.entityName(given.giverID))  →  \(data.entityName(given.recipientID))")
        #expect(!data.giftSubtitle(given).contains("·"))
    }
}
