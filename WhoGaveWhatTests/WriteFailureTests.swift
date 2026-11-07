import Foundation
import Testing

@testable import WhoGaveWhat

/// Issue #85: a refused save or deletion keeps the draft, the screen and the stored records, says so,
/// and a retry does what the first attempt should have done.
@MainActor
struct GiftSaveFailureTests {
    private let giftDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 8))!

    /// A new-gift sheet with every field set, opened from People so the switch to Home is visible.
    private func filledCreateSheet(_ fixture: FailableComposition, analytics: AnalyticsGateway) -> AddGiftState {
        let composition = fixture.composition
        composition.router.tab = .people
        composition.router.presentNewGift(from: .floatingButton)
        let state = AddGiftState(route: .create, data: composition.data, suggestGift: composition.suggestGift, analytics: analytics)
        state.name = "Silk scarf"
        state.selectFrom("maria")
        state.selectTo("anton")
        state.selectDate(giftDate)
        state.valueText = "45"
        state.selectOccasion("Birthday")
        state.selectEmoji("🧣")
        state.draft.paidByYou = true
        return state
    }

    @Test func aFailedCreateKeepsTheSheetAndEveryValue() throws {
        let analytics = RecordingAnalyticsGateway()
        let haptics = RecordingHapticsGateway()
        let fixture = try FailableComposition(analytics: analytics, haptics: haptics)
        let composition = fixture.composition
        let state = filledCreateSheet(fixture, analytics: analytics)
        let draft = state.draft
        let storedBefore = try fixture.storedGifts()
        let shownBefore = composition.data.gifts
        fixture.gifts.failingSaves = 1
        analytics.events.removeAll()

        state.save(using: composition)

        #expect(state.isShowingSaveError)
        #expect(state.draft == draft)
        #expect(state.name == "Silk scarf")
        #expect(state.draft.fromID == "maria" && state.draft.toID == "anton")
        #expect(state.draft.date == giftDate)
        #expect(state.valueText == "45")
        #expect(state.draft.occasion == "Birthday")
        #expect(state.effectiveEmoji == "🧣")
        #expect(state.input.canSave)
        #expect(composition.router.giftSheet == .create)
        #expect(composition.router.tab == .people)
        #expect(try fixture.storedGifts() == storedBefore)
        #expect(composition.data.gifts == shownBefore)
        #expect(analytics.events == [.giftSaveAttempted(mode: .create), .giftSaveFailed(mode: .create)])
        #expect(analytics.failures.map(\.operation) == ["save_gift"])
        #expect(haptics.played == [.error])
    }

    @Test func aRetryAfterAFailedCreateStoresExactlyOneGiftAndCloses() throws {
        let analytics = RecordingAnalyticsGateway()
        let haptics = RecordingHapticsGateway()
        let fixture = try FailableComposition(analytics: analytics, haptics: haptics)
        let composition = fixture.composition
        let state = filledCreateSheet(fixture, analytics: analytics)
        let storedBefore = try fixture.storedGifts()
        fixture.gifts.failingSaves = 1
        analytics.events.removeAll()

        state.save(using: composition)
        state.isShowingSaveError = false  // The user taps OK on the alert, then Save again.
        state.save(using: composition)

        let stored = try fixture.storedGifts()
        #expect(stored.count == storedBefore.count + 1)
        let added = stored.filter { gift in !storedBefore.contains { $0.id == gift.id } }
        #expect(added.count == 1)
        let gift = try #require(added.first)
        #expect(gift.name == "Silk scarf")
        #expect(gift.giverID == "maria" && gift.recipientID == "anton")
        #expect(gift.date == giftDate)
        #expect(gift.value == 45)
        #expect(gift.occasion == "Birthday")
        #expect(gift.emoji == "🧣" && gift.emojiPickedByUser)
        #expect(gift.paidByYou)
        #expect(composition.data.gifts.filter { $0.name == "Silk scarf" }.count == 1)
        #expect(!state.isShowingSaveError)
        #expect(composition.router.giftSheet == nil)
        #expect(composition.router.tab == .home)
        #expect(
            analytics.events.map(\.name) == [
                "gift_save_attempted", "gift_save_failed", "gift_save_attempted", "gift_saved", "gift_sheet_closed"
            ])
        #expect(analytics.events.last == .giftSheetClosed(mode: .create, outcome: .saved))
        #expect(haptics.played == [.error, .success])
    }

    @Test func aFailedEditKeepsTheStoredGiftAndTheEdits() throws {
        let analytics = RecordingAnalyticsGateway()
        let haptics = RecordingHapticsGateway()
        let fixture = try FailableComposition(analytics: analytics, haptics: haptics)
        let composition = fixture.composition
        let original = try #require(composition.data.gifts.first)
        composition.router.presentEditGift(id: original.id)
        let state = AddGiftState(
            route: .edit(giftID: original.id), data: composition.data, suggestGift: composition.suggestGift, analytics: analytics)
        state.name = "Renamed gift"
        state.selectFrom(original.recipientID)
        state.selectTo(original.giverID)
        state.selectDate(giftDate)
        state.valueText = "321"
        state.selectOccasion("New Year")
        state.selectEmoji("🎄")
        let draft = state.draft
        let storedBefore = try fixture.storedGifts()
        fixture.gifts.failingSaves = 1
        analytics.events.removeAll()

        state.save(using: composition)

        #expect(state.isShowingSaveError)
        #expect(state.draft == draft)
        #expect(composition.router.giftSheet == .edit(giftID: original.id))
        #expect(try fixture.storedGifts() == storedBefore)
        #expect(composition.data.gifts.first { $0.id == original.id } == original)
        #expect(analytics.events == [.giftSaveAttempted(mode: .edit), .giftSaveFailed(mode: .edit)])
        #expect(haptics.played == [.error])

        state.isShowingSaveError = false
        state.save(using: composition)

        let stored = try fixture.storedGifts()
        #expect(stored.count == storedBefore.count)
        let edited = try #require(stored.first { $0.id == original.id })
        #expect(edited.name == "Renamed gift")
        #expect(edited.giverID == original.recipientID && edited.recipientID == original.giverID)
        #expect(edited.date == giftDate)
        #expect(edited.value == 321)
        #expect(edited.occasion == "New Year")
        #expect(edited.emoji == "🎄")
        #expect(edited.createdAt == original.createdAt)
        #expect(composition.router.giftSheet == nil)
        #expect(analytics.events.last == .giftSheetClosed(mode: .edit, outcome: .saved))
        #expect(haptics.played == [.error, .success])
    }

    @Test func aFailedSaveIsNotAClosedSheetAndCancellingLaterIsACancel() throws {
        let analytics = RecordingAnalyticsGateway()
        let fixture = try FailableComposition(analytics: analytics)
        let state = filledCreateSheet(fixture, analytics: analytics)
        fixture.gifts.failingSaves = 1

        state.save(using: fixture.composition)
        #expect(!analytics.eventNames.contains("gift_sheet_closed"))
        #expect(!analytics.eventNames.contains("gift_saved"))

        fixture.composition.router.dismissGiftSheet()
        #expect(analytics.events.last == .giftSheetClosed(mode: .create, outcome: .cancelled))
    }

    @Test func theFailureReportCarriesNoGiftContent() throws {
        let analytics = RecordingAnalyticsGateway()
        let fixture = try FailableComposition(analytics: analytics)
        let state = filledCreateSheet(fixture, analytics: analytics)
        fixture.gifts.failingSaves = 1

        state.save(using: fixture.composition)

        let failure = try #require(analytics.failures.first)
        #expect(failure.operation == "save_gift")
        #expect(failure.message == nil)
        #expect(failure.details.isEmpty)
        let sanitized = SentryCrashReportingGateway.sanitized(try #require(failure.error))
        #expect(!sanitized.localizedDescription.contains("Silk"))
        for event in analytics.events {
            #expect(!event.properties.values.contains(.string("Silk scarf")))
        }
    }
}

@MainActor
struct DeletionFailureTests {
    @Test func aFailedGiftDeletionKeepsTheGiftAndReportsFailure() throws {
        let analytics = RecordingAnalyticsGateway()
        let haptics = RecordingHapticsGateway()
        let fixture = try FailableComposition(analytics: analytics, haptics: haptics)
        let composition = fixture.composition
        let gift = try #require(composition.data.gifts.first)
        let storedBefore = try fixture.storedGifts()
        fixture.gifts.failingDeletes = 1

        #expect(composition.deleteGift(id: gift.id, source: .giftDetail) == .failed)

        #expect(try fixture.storedGifts() == storedBefore)
        #expect(composition.data.gifts.contains(gift))
        #expect(!analytics.eventNames.contains("gift_deleted"))
        #expect(analytics.failures.map(\.operation) == ["delete_gift"])
        #expect(haptics.played == [.error])

        #expect(composition.deleteGift(id: gift.id, source: .giftDetail) == .deleted)

        #expect(try fixture.storedGifts().count == storedBefore.count - 1)
        #expect(!composition.data.gifts.contains { $0.id == gift.id })
        #expect(analytics.eventNames == ["gift_deleted"])
        #expect(haptics.played == [.error])
    }

    @Test func aFailedPersonDeletionKeepsThePersonTheirGiftsAndTheViewpoint() throws {
        let analytics = RecordingAnalyticsGateway()
        let haptics = RecordingHapticsGateway()
        let selfID = SwiftDataStore.seedSelfPersonID
        let fixture = try FailableComposition(selfPersonID: selfID, analytics: analytics, haptics: haptics)
        let composition = fixture.composition
        let peopleBefore = try fixture.storedPeople()
        let giftsBefore = try fixture.storedGifts()
        #expect(giftsBefore.contains { $0.giverID == selfID || $0.recipientID == selfID })
        fixture.people.failingDeletes = 1

        #expect(composition.deletePerson(id: selfID, source: .personEditor) == .failed)

        #expect(try fixture.storedPeople() == peopleBefore)
        #expect(try fixture.storedGifts() == giftsBefore)
        #expect(composition.data.people.contains { $0.id == selfID })
        #expect(composition.data.gifts == giftsBefore)
        #expect(composition.data.selfPersonID == selfID)
        #expect(fixture.preferences.selfPersonID == selfID)
        #expect(!analytics.eventNames.contains("person_deleted"))
        #expect(analytics.failures.map(\.operation) == ["delete_person"])
        #expect(haptics.played == [.error])

        #expect(composition.deletePerson(id: selfID, source: .personEditor) == .deleted)

        #expect(!composition.data.people.contains { $0.id == selfID })
        #expect(!composition.data.gifts.contains { $0.giverID == selfID || $0.recipientID == selfID })
        #expect(composition.data.selfPersonID == nil)
        #expect(analytics.eventNames == ["person_deleted"])
    }

    @Test func aFailedListDeletionOfSomeoneElseKeepsThem() throws {
        let fixture = try FailableComposition()
        let composition = fixture.composition
        let peopleBefore = try fixture.storedPeople()
        fixture.people.failingDeletes = 1

        #expect(composition.deletePerson(id: "maria", source: .peopleList) == .failed)
        #expect(try fixture.storedPeople() == peopleBefore)
        #expect(composition.data.people.contains { $0.id == "maria" })
    }
}

/// The Debug-only `KS_FAIL_SAVE` / `KS_FAIL_DELETE` launch switches used to show the error states on a simulator.
@MainActor
struct WriteFailureInjectionTests {
    @Test func launchFlagsFailOnlyTheNextWrites() throws {
        let fixture = try FailableComposition(launchEnvironment: ["KS_FAIL_SAVE": "1", "KS_FAIL_DELETE": "2"])
        let composition = fixture.composition
        let input = makeGiftInput(name: "Scarf", fromID: "maria", toID: "anton")
        let gift = try #require(composition.data.gifts.first)

        #expect(composition.saveGift(input) == .failed)
        #expect(composition.saveGift(input) == .saved)
        #expect(composition.deleteGift(id: gift.id, source: .home) == .failed)
        #expect(composition.deletePerson(id: "maria", source: .peopleList) == .failed)
        #expect(composition.deleteGift(id: gift.id, source: .home) == .deleted)
        #expect(composition.deletePerson(id: "maria", source: .peopleList) == .deleted)
    }

    @Test func missingOrInvalidFlagsLeaveWritesAlone() {
        #expect(!WriteFailureInjection(launchEnvironment: [:]).isActive)
        #expect(!WriteFailureInjection(launchEnvironment: ["KS_FAIL_SAVE": "yes", "KS_FAIL_DELETE": "-2"]).isActive)
        #expect(WriteFailureInjection(launchEnvironment: ["KS_FAIL_DELETE": "1"]).isActive)
    }
}
