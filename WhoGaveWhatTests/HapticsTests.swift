import Foundation
import Testing

@testable import WhoGaveWhat

@MainActor
struct CompositionHapticsTests {
    private func makeComposition(hasViewpoint: Bool = true) throws -> (AppComposition, RecordingHapticsGateway) {
        let haptics = RecordingHapticsGateway()
        let selfPersonID = hasViewpoint ? SwiftDataStore.seedSelfPersonID : nil
        return (try makeTestComposition(selfPersonID: selfPersonID, haptics: haptics), haptics)
    }

    @Test func everySuccessfulGiftSavePlaysSuccess() throws {
        let (composition, haptics) = try makeComposition()

        #expect(composition.saveGift(makeGiftInput(name: "Scarf", fromID: "maria", toID: "anton")))
        #expect(composition.saveGift(makeGiftInput(name: "Book", fromID: "maria", toID: "anton")))

        #expect(haptics.played == [.success, .success])
    }

    @Test func editingAGiftPlaysSuccess() throws {
        let (composition, haptics) = try makeComposition()
        let gift = try #require(composition.data.gifts.first)
        var input = makeGiftInput(name: "Renamed", fromID: gift.giverID, toID: gift.recipientID)
        input.editingGiftID = gift.id
        input.createdAt = gift.createdAt

        #expect(composition.saveGift(input))

        #expect(haptics.played == [.success])
    }

    @Test func aFailedGiftSaveIsSilent() throws {
        let (composition, haptics) = try makeComposition()

        #expect(!composition.saveGift(makeGiftInput(name: "", fromID: "maria", toID: "anton")))

        #expect(haptics.played.isEmpty)
    }

    @Test func creatingANewPersonPlaysSuccess() throws {
        let (composition, haptics) = try makeComposition()

        _ = try #require(composition.createPerson(name: "Dana", source: .peopleTab))

        #expect(haptics.played == [.success])
    }

    @Test func creatingAnExistingNameIsSilent() throws {
        let (composition, haptics) = try makeComposition()
        let existing = try #require(composition.data.people.first)

        _ = composition.createPerson(name: existing.name, source: .giftPicker)

        #expect(haptics.played.isEmpty)
    }

    @Test func updatingAPersonPlaysSuccess() throws {
        let (composition, haptics) = try makeComposition()
        let person = try #require(composition.data.people.first)

        try composition.updatePerson(id: person.id, name: "Renamed", imageData: nil)

        #expect(haptics.played == [.success])
    }

    @Test func aDuplicateNameUpdatePlaysNothingFromTheComposition() throws {
        let (composition, haptics) = try makeComposition()
        let people = composition.data.people
        let first = try #require(people.first)
        let second = try #require(people.dropFirst().first)

        #expect(throws: PersonUpdateError.self) {
            try composition.updatePerson(id: first.id, name: second.name, imageData: nil)
        }

        #expect(haptics.played.isEmpty)
    }

    @Test func settingsViewpointPicksAndDeletesAreSilent() throws {
        let (composition, haptics) = try makeComposition(hasViewpoint: false)
        let gift = try #require(composition.data.gifts.first)
        let removable = try #require(composition.createPerson(name: "Dana", source: .peopleTab))
        haptics.played.removeAll()

        composition.markSelf(true, personID: "anton")
        composition.setCurrencyCode("RUB")
        composition.setCloudIconConsent(.allowed)
        composition.setAnalyticsEnabled(false)
        composition.recordInsightsPick("maria", for: .subject)
        composition.deleteGift(id: gift.id, source: .giftDetail)
        composition.deletePerson(id: removable, source: .personEditor)

        #expect(haptics.played.isEmpty)
    }
}

struct HapticFeedbackTests {
    @MainActor
    @Test func personSaveFailureMatchesTheEditorsMessages() {
        #expect(HapticFeedback.personSaveFailure(PersonUpdateError.duplicateName) == .warning)
        #expect(HapticFeedback.personSaveFailure(CocoaError(.fileWriteUnknown)) == .error)
    }
}

struct HapticThrottleTests {
    /// Feeds `(feedback, time)` requests through a fresh throttle and returns which ones played.
    private func results(_ requests: [(HapticFeedback, TimeInterval)]) -> [Bool] {
        var throttle = HapticThrottle()
        return requests.map { throttle.shouldPlay($0.0, at: $0.1) }
    }

    @Test func notificationsAlwaysPlay() {
        let played = results([(.success, 0), (.success, 0), (.warning, 0.01), (.error, 0.02)])

        #expect(played == [true, true, true, true])
    }

    @Test func lightTicksAreDroppedShortlyAfterAnyPlayedHaptic() {
        let played = results([
            (.selection, 0),
            (.selection, 0.119),
            (.softImpact, 0.05),
            (.softImpact, 0.12),
            (.success, 0.125),
            (.selection, 0.2),
            (.selection, 0.25)
        ])

        #expect(played == [true, false, false, true, true, false, true])
    }

    @Test func aDroppedRequestDoesNotExtendTheQuietPeriod() {
        // The third request is measured from the first play, not from the dropped 0.1 request.
        let played = results([(.selection, 0), (.selection, 0.1), (.selection, 0.12)])

        #expect(played == [true, false, true])
    }
}
