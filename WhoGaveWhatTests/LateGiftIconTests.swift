import Foundation
import Testing

@testable import WhoGaveWhat

/// A gift saved before the model answered still gets its icon: the request outlives the sheet.
@MainActor
struct LateGiftIconTests {
    @MainActor
    private struct Fixture {
        let composition: AppComposition
        let cloud: ScriptedIntelligenceGateway
        let analytics: RecordingAnalyticsGateway

        func makeSheet(route: GiftSheetRoute = .create, debounce: Duration = .milliseconds(5)) -> AddGiftState {
            AddGiftState(
                route: route,
                data: composition.data,
                suggestGift: composition.suggestGift,
                debounce: debounce,
                analytics: analytics)
        }

        func gift(named name: String) -> Gift? {
            composition.data.gifts.first { $0.name == name }
        }
    }

    private func makeFixture() throws -> Fixture {
        let cloud = ScriptedIntelligenceGateway()
        cloud.results["Skateboard"] = GiftIntelligenceResult(emoji: "🛹", value: 120)
        let analytics = RecordingAnalyticsGateway()
        let composition = AppComposition(
            store: try SwiftDataStore(inMemory: true, seed: true),
            preferences: TestPreferencesGateway(),
            intelligence: PreferredGiftIntelligenceGateway(cloud: cloud, onDevice: TestIntelligenceGateway()),
            analytics: analytics)
        return Fixture(composition: composition, cloud: cloud, analytics: analytics)
    }

    private func fill(_ sheet: AddGiftState, name: String) {
        sheet.setName(name)
        sheet.previewFrom("marina")
        sheet.previewTo("anton")
    }

    /// The sheet closes after Save, which cancels whatever it still runs, as `onDisappear` does.
    private func saveAndClose(_ sheet: AddGiftState, in composition: AppComposition) {
        sheet.save(using: composition)
        sheet.cancel()
    }

    @Test func quickSaveKeepsTheSentRequestAndAppliesItsIcon() async throws {
        let fixture = try makeFixture()
        fixture.cloud.holdsRequests = true
        let sheet = fixture.makeSheet()
        fill(sheet, name: "Skateboard")
        await fixture.cloud.waitForRequests(1)

        saveAndClose(sheet, in: fixture.composition)
        let saved = try #require(fixture.gift(named: "Skateboard"))
        #expect(saved.emoji == "🎁")
        #expect(fixture.composition.pendingGiftIcons.contains(saved.id))

        fixture.cloud.releaseRequests()
        await fixture.composition.pendingGiftIcons.task(for: saved.id)?.value

        let updated = try #require(fixture.gift(named: "Skateboard"))
        #expect(updated.emoji == "🛹")
        #expect(updated.emojiPickedByUser == false)
        // Only the icon arrives late; the saved value is left alone.
        #expect(updated.value == saved.value)
        #expect(updated.lastSavedAt == saved.lastSavedAt)
        #expect(!fixture.composition.pendingGiftIcons.contains(saved.id))
        // The request the sheet had sent is reused, not sent twice.
        #expect(fixture.cloud.requests == ["Skateboard"])
        let afterSave = fixture.analytics.events.compactMap { event -> Bool? in
            if case .giftSuggestionCompleted(_, let hasIcon, _, _, let afterSave) = event, hasIcon { afterSave } else { nil }
        }
        #expect(afterSave == [true])
    }

    @Test func saveBeforeTheRequestWasSentSendsItOnce() async throws {
        let fixture = try makeFixture()
        let sheet = fixture.makeSheet(debounce: .seconds(30))
        fill(sheet, name: "Skateboard")

        saveAndClose(sheet, in: fixture.composition)
        let saved = try #require(fixture.gift(named: "Skateboard"))
        #expect(saved.emoji == "🎁")
        await fixture.composition.pendingGiftIcons.task(for: saved.id)?.value
        await sheet.suggestionTask?.value

        #expect(fixture.gift(named: "Skateboard")?.emoji == "🛹")
        #expect(fixture.cloud.requests == ["Skateboard"])
    }

    @Test func anAnswerThatArrivedInTheSheetNeedsNoFollowUp() async throws {
        let fixture = try makeFixture()
        let sheet = fixture.makeSheet()
        fill(sheet, name: "Skateboard")
        await sheet.suggestionTask?.value

        #expect(sheet.pendingIconRequest == nil)
        saveAndClose(sheet, in: fixture.composition)

        #expect(fixture.gift(named: "Skateboard")?.emoji == "🛹")
        #expect(fixture.composition.pendingGiftIcons.giftIDs.isEmpty)
        #expect(fixture.cloud.requests == ["Skateboard"])
    }

    @Test func aHandPickedIconIsNotFollowed() async throws {
        let fixture = try makeFixture()
        fixture.cloud.holdsRequests = true
        let sheet = fixture.makeSheet()
        fill(sheet, name: "Skateboard")
        await fixture.cloud.waitForRequests(1)
        sheet.selectEmoji("🐶")

        #expect(sheet.pendingIconRequest == nil)
        saveAndClose(sheet, in: fixture.composition)
        fixture.cloud.releaseRequests()

        #expect(fixture.composition.pendingGiftIcons.giftIDs.isEmpty)
        #expect(fixture.gift(named: "Skateboard")?.emoji == "🐶")
    }

    @Test func aFailedSaveKeepsTheRequestInTheSheet() async throws {
        let failing = try FailableComposition()
        let cloud = ScriptedIntelligenceGateway()
        cloud.holdsRequests = true
        cloud.results["Skateboard"] = GiftIntelligenceResult(emoji: "🛹", value: nil)
        let suggest = SuggestGiftUseCase(
            intelligenceGateway: PreferredGiftIntelligenceGateway(cloud: cloud, onDevice: TestIntelligenceGateway()))
        let sheet = AddGiftState(
            route: .create, data: failing.composition.data, suggestGift: suggest, debounce: .milliseconds(5))
        fill(sheet, name: "Skateboard")
        await cloud.waitForRequests(1)
        failing.gifts.failingSaves = 1

        sheet.save(using: failing.composition)
        #expect(sheet.isShowingSaveError)
        #expect(failing.composition.pendingGiftIcons.giftIDs.isEmpty)

        cloud.releaseRequests()
        await sheet.suggestionTask?.value
        #expect(sheet.effectiveEmoji == "🛹")
    }

    @Test func aLateIconSkipsAGiftThatChangedMeanwhile() async throws {
        let fixture = try makeFixture()
        fixture.cloud.holdsRequests = true
        for name in ["Skateboard", "Skateboard deck", "Skateboard wheels"] {
            let sheet = fixture.makeSheet()
            fill(sheet, name: name)
            await fixture.cloud.waitForRequests(fixture.cloud.requests.count + 1)
            saveAndClose(sheet, in: fixture.composition)
        }
        fixture.cloud.results["Skateboard deck"] = GiftIntelligenceResult(emoji: "🛹", value: nil)
        fixture.cloud.results["Skateboard wheels"] = GiftIntelligenceResult(emoji: "🛹", value: nil)
        let picked = try #require(fixture.gift(named: "Skateboard"))
        let renamed = try #require(fixture.gift(named: "Skateboard deck"))
        let deleted = try #require(fixture.gift(named: "Skateboard wheels"))

        // The user picks an icon for one gift, renames another and deletes the third.
        let pickSheet = fixture.makeSheet(route: .edit(giftID: picked.id))
        pickSheet.selectEmoji("🐶")
        saveAndClose(pickSheet, in: fixture.composition)
        let renameSheet = fixture.makeSheet(route: .edit(giftID: renamed.id), debounce: .seconds(30))
        renameSheet.setName("Bike")
        renameSheet.selectEmoji("🚲")
        saveAndClose(renameSheet, in: fixture.composition)
        #expect(fixture.composition.deleteGift(id: deleted.id, source: .home) == .deleted)

        fixture.cloud.releaseRequests()
        for gift in [picked, renamed, deleted] {
            await fixture.composition.pendingGiftIcons.task(for: gift.id)?.value
        }

        #expect(fixture.composition.data.gifts.first { $0.id == picked.id }?.emoji == "🐶")
        #expect(fixture.composition.data.gifts.first { $0.id == renamed.id }?.emoji == "🚲")
        #expect(fixture.composition.data.gifts.contains { $0.id == deleted.id } == false)
        #expect(fixture.composition.pendingGiftIcons.giftIDs.isEmpty)
    }

    @Test func anEditSheetOpenWhileTheIconLandsKeepsIt() async throws {
        let fixture = try makeFixture()
        fixture.cloud.holdsRequests = true
        let sheet = fixture.makeSheet()
        fill(sheet, name: "Skateboard")
        await fixture.cloud.waitForRequests(1)
        saveAndClose(sheet, in: fixture.composition)
        let saved = try #require(fixture.gift(named: "Skateboard"))

        let editSheet = fixture.makeSheet(route: .edit(giftID: saved.id))
        #expect(editSheet.effectiveEmoji == "🎁")
        fixture.cloud.releaseRequests()
        await fixture.composition.pendingGiftIcons.task(for: saved.id)?.value
        editSheet.valueText = "150"
        saveAndClose(editSheet, in: fixture.composition)

        let edited = try #require(fixture.gift(named: "Skateboard"))
        #expect(edited.emoji == "🛹")
        #expect(edited.value == 150)
    }

    @Test func aNewerSaveReplacesTheEarlierRequest() async throws {
        let fixture = try makeFixture()
        fixture.cloud.holdsRequests = true
        fixture.cloud.results["Longboard"] = GiftIntelligenceResult(emoji: "🏄", value: nil)
        let sheet = fixture.makeSheet()
        fill(sheet, name: "Skateboard")
        await fixture.cloud.waitForRequests(1)
        saveAndClose(sheet, in: fixture.composition)
        let saved = try #require(fixture.gift(named: "Skateboard"))

        let editSheet = fixture.makeSheet(route: .edit(giftID: saved.id))
        editSheet.setName("Longboard")
        await fixture.cloud.waitForRequests(2)
        saveAndClose(editSheet, in: fixture.composition)
        fixture.cloud.releaseRequests()
        await fixture.composition.pendingGiftIcons.task(for: saved.id)?.value

        #expect(fixture.composition.data.gifts.first { $0.id == saved.id }?.emoji == "🏄")
        #expect(fixture.composition.pendingGiftIcons.giftIDs.isEmpty)
    }

    @Test func applyingALateIconKeepsTheRestOfTheGift() throws {
        let gateway = TestGiftGateway()
        let gift = Gift(
            id: "g1", emoji: "🎁", name: "Skateboard", giverID: "a", recipientID: "b", paidByYou: false,
            occasion: "Birthday", date: AppDate.today, value: 0, currency: .usd,
            createdAt: Date(timeIntervalSince1970: 0), lastSavedAt: Date(timeIntervalSince1970: 10))
        let useCase = ApplyLateGiftIconUseCase(giftGateway: gateway)

        #expect(try useCase.execute(emoji: "🛹", giftID: "g1", requestedName: "Skateboard", gifts: [gift]))
        var expected = gift
        expected.emoji = "🛹"
        #expect(gateway.gifts == [expected])

        // The same icon, another name or a picked icon change nothing.
        #expect(!(try useCase.execute(emoji: "🛹", giftID: "g1", requestedName: "Skateboard", gifts: [expected])))
        #expect(!(try useCase.execute(emoji: "🛹", giftID: "g1", requestedName: "Bike", gifts: [gift])))
        var picked = gift
        picked.emojiPickedByUser = true
        #expect(!(try useCase.execute(emoji: "🛹", giftID: "g1", requestedName: "Skateboard", gifts: [picked])))
        #expect(!(try useCase.execute(emoji: "🛹", giftID: "g2", requestedName: "Skateboard", gifts: [gift])))
    }
}
