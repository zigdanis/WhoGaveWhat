import Foundation
import Testing

@testable import WhoGaveWhat

/// "Add a gift" on a person's screen opens the sheet with that person already in it, and the
/// swap button turns the gift around in one tap.
@MainActor
struct PersonAddGiftTests {
    private func sheetState(
        for personID: String,
        in composition: AppComposition,
        analytics: AnalyticsGateway = NoopAnalyticsGateway()
    ) -> AddGiftState {
        AddGiftState(
            route: .createWithPerson(personID: personID), data: composition.data,
            suggestGift: composition.suggestGift, analytics: analytics)
    }

    @Test func thePersonScreenOpensTheSheetWithThatPerson() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)

        composition.router.presentNewGift(from: .personDetail, personID: "maria")

        #expect(composition.router.giftSheet == .createWithPerson(personID: "maria"))
        #expect(composition.router.giftSheet?.mode == .create)
        #expect(analytics.events.last == .giftSheetOpened(mode: .create, source: .personDetail))
        #expect(analytics.events.last?.properties["source"] == .string("person_detail"))

        composition.router.presentNewGift(from: .personWelcome, personID: "maria")
        #expect(analytics.events.last?.properties["source"] == .string("person_welcome"))
    }

    @Test func thePersonGivesToTheViewpoint() throws {
        let composition = try makeTestComposition(selfPersonID: "anton")
        let state = sheetState(for: "maria", in: composition)

        #expect(state.draft.fromID == "maria")
        #expect(state.draft.toID == "anton")
        #expect(state.editingGiftID == nil)
    }

    @Test func withoutAViewpointOnlyThePersonIsChosen() throws {
        let composition = try makeTestComposition(selfPersonID: nil)
        let state = sheetState(for: "maria", in: composition)

        #expect(state.draft.fromID == "maria")
        #expect(state.draft.toID == nil)
    }

    @Test func theViewpointsOwnScreenMakesThemTheRecipient() throws {
        let composition = try makeTestComposition(selfPersonID: "anton")
        let state = sheetState(for: "anton", in: composition)

        #expect(state.draft.fromID == nil)
        #expect(state.draft.toID == "anton")
    }

    @Test func aPersonWhoIsGoneLeavesBothSidesEmpty() throws {
        let composition = try makeTestComposition(selfPersonID: "anton")
        let state = sheetState(for: "deleted-person", in: composition)

        #expect(state.draft.fromID == nil)
        #expect(state.draft.toID == nil)
    }

    @Test func swapTurnsTheGiftAround() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(selfPersonID: "anton")
        let state = sheetState(for: "maria", in: composition, analytics: analytics)

        #expect(state.canSwapPeople)
        state.swapPeople()

        #expect(state.draft.fromID == "anton")
        #expect(state.draft.toID == "maria")
        #expect(analytics.events == [.giftPeopleSwapped])
        #expect(analytics.events.last?.name == "gift_people_swapped")
    }

    @Test func swapMovesASingleChosenSide() throws {
        let composition = try makeTestComposition(selfPersonID: nil)
        let state = sheetState(for: "maria", in: composition)

        state.swapPeople()

        #expect(state.draft.fromID == nil)
        #expect(state.draft.toID == "maria")
    }

    @Test func swapDoesNothingWithBothSidesEmpty() throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition()
        let state = AddGiftState(
            route: .create, data: composition.data, suggestGift: composition.suggestGift, analytics: analytics)

        #expect(!state.canSwapPeople)
        state.swapPeople()

        #expect(state.draft.fromID == nil && state.draft.toID == nil)
        #expect(analytics.events.isEmpty)
    }

    @Test func aGiftSavedFromThePersonScreenStaysThere() throws {
        let composition = try makeTestComposition(selfPersonID: "anton")
        composition.router.tab = .people
        composition.router.presentNewGift(from: .personDetail, personID: "maria")
        let state = sheetState(for: "maria", in: composition)
        state.name = "Silk scarf"

        state.save(using: composition)

        #expect(composition.router.giftSheet == nil)
        #expect(composition.router.tab == .people)
        let saved = try #require(composition.data.gifts.first { $0.name == "Silk scarf" })
        #expect(saved.giverID == "maria" && saved.recipientID == "anton")
    }
}
