import Testing

@testable import WhoGaveWhat

@MainActor
struct CloudIconConsentStateTests {
    private func makeState(
        preferences: TestPreferencesGateway,
        cloud: ScriptedIntelligenceGateway,
        data: AppData
    ) -> AddGiftState {
        let intelligence = PreferredGiftIntelligenceGateway(
            preferences: preferences,
            cloud: cloud,
            onDevice: TestIntelligenceGateway()
        )
        return AddGiftState(
            route: .create,
            data: data,
            suggestGift: SuggestGiftUseCase(intelligenceGateway: intelligence),
            preferences: preferences,
            debounce: .milliseconds(5)
        )
    }

    @Test func consentCardRequiresTypingAnEligibleNameWithoutManualEmoji() throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        let state = makeState(preferences: preferences, cloud: ScriptedIntelligenceGateway(), data: composition.data)
        #expect(state.showsCloudIconConsent == false)
        state.setName("  я \n")
        #expect(state.showsCloudIconConsent == false)
        state.setName("  гитара \n")
        #expect(state.showsCloudIconConsent)
        state.selectEmoji("🐶")
        #expect(state.showsCloudIconConsent == false)
    }

    @Test func allowPersistsConsentAndImmediatelySuggestsForCurrentName() async throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        let cloud = ScriptedIntelligenceGateway()
        cloud.results["гитара"] = GiftIntelligenceResult(emoji: "🎸", value: 0)
        let state = makeState(preferences: preferences, cloud: cloud, data: composition.data)
        state.setName("гитара")
        #expect(state.suggestionTask == nil)
        #expect(state.showsCloudIconConsent)

        state.allowCloudIcons()
        await state.suggestionTask?.value

        #expect(preferences.cloudIconConsent == .allowed)
        #expect(state.showsCloudIconConsent == false)
        #expect(cloud.requests == ["гитара"])
        #expect(state.draft.aiEmoji == "🎸")
        #expect(state.effectiveEmoji == "🎸")
        #expect(state.draft.value == nil)
        #expect(state.draft.valueTouched == false)
    }

    @Test func decliningHidesPromptAcrossTypingAndNewSheets() throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        let cloud = ScriptedIntelligenceGateway()
        let state = makeState(preferences: preferences, cloud: cloud, data: composition.data)
        state.setName("гитара")
        #expect(state.showsCloudIconConsent)
        state.declineCloudIcons()

        #expect(preferences.cloudIconConsent == .declined)
        #expect(state.showsCloudIconConsent == false)
        state.setName("кроссовки")
        #expect(state.showsCloudIconConsent == false)
        let reopened = makeState(preferences: preferences, cloud: cloud, data: composition.data)
        reopened.setName("гитара")
        #expect(reopened.showsCloudIconConsent == false)
        #expect(cloud.requests.isEmpty)
    }

    @Test func manualPickBeatsLateCloudAnswer() async throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        preferences.setCloudIconConsent(.allowed)
        let cloud = ScriptedIntelligenceGateway()
        cloud.holdsRequests = true
        cloud.results["гитара"] = GiftIntelligenceResult(emoji: "🎸", value: 0)
        let state = makeState(preferences: preferences, cloud: cloud, data: composition.data)
        state.setName("гитара")
        await cloud.waitForRequests(1)
        let task = state.suggestionTask

        state.selectEmoji("🐶")
        cloud.releaseRequests()
        await task?.value

        #expect(state.effectiveEmoji == "🐶")
        #expect(state.draft.aiEmoji == nil)
        #expect(state.aiLoading == false)
        #expect(state.showsCloudIconConsent == false)
    }

    @Test func staleCloudAnswerCannotReplaceLatestName() async throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        preferences.setCloudIconConsent(.allowed)
        let cloud = ScriptedIntelligenceGateway()
        cloud.holdsRequests = true
        cloud.results["гитара"] = GiftIntelligenceResult(emoji: "🎸", value: 0)
        cloud.results["кроссовки"] = GiftIntelligenceResult(emoji: "👟", value: 0)
        let state = makeState(preferences: preferences, cloud: cloud, data: composition.data)
        state.setName("гитара")
        await cloud.waitForRequests(1)
        let first = state.suggestionTask
        state.setName("кроссовки")
        cloud.releaseRequests()
        await first?.value
        #expect(state.draft.aiEmoji == nil)

        await cloud.waitForRequests(2)
        cloud.releaseRequests()
        await state.suggestionTask?.value
        #expect(state.draft.aiEmoji == "👟")
        #expect(state.aiLoading == false)
    }

    @Test func cloudNilKeepsHeuristicAndNeverBlocksSaving() async throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        preferences.setCloudIconConsent(.allowed)
        let state = makeState(preferences: preferences, cloud: ScriptedIntelligenceGateway(), data: composition.data)
        state.setName("bouquet")
        let people = composition.data.people.map(\.id)
        state.previewFrom(people[0])
        state.previewTo(people[1])
        #expect(state.input.canSave)
        await state.suggestionTask?.value
        #expect(state.effectiveEmoji == "💐")
        #expect(state.input.canSave)
    }

    @Test func cloudNilKeepsSavedEmojiWhenRenamedWithoutKeywordMatch() async throws {
        let composition = try makeTestComposition()
        let gift = try #require(composition.data.gifts.first { !$0.emojiPickedByUser && $0.emoji != "🎁" })
        let preferences = TestPreferencesGateway()
        preferences.setCloudIconConsent(.allowed)
        let cloud = ScriptedIntelligenceGateway()
        let gateway = PreferredGiftIntelligenceGateway(
            preferences: preferences, cloud: cloud, onDevice: TestIntelligenceGateway()
        )
        let state = AddGiftState(
            route: .edit(giftID: gift.id),
            data: composition.data,
            suggestGift: SuggestGiftUseCase(intelligenceGateway: gateway),
            preferences: preferences,
            debounce: .milliseconds(5)
        )
        state.setName("zz unknown thing")
        await state.suggestionTask?.value

        #expect(state.effectiveEmoji == gift.emoji)
        #expect(state.input.aiEmoji == gift.emoji)
        #expect(cloud.requests == ["zz unknown thing"])
    }

    @Test func verificationLaunchCanOverrideConsent() throws {
        let preferences = TestPreferencesGateway()
        let composition = AppComposition(
            store: try SwiftDataStore(inMemory: true, seed: true),
            preferences: preferences,
            intelligence: TestIntelligenceGateway(),
            launchEnvironment: ["KS_CLOUD_ICON_CONSENT": "allowed"]
        )
        #expect(composition.cloudIconConsent == .allowed)
        let installID = preferences.installID
        composition.setCloudIconConsent(.declined)
        #expect(composition.cloudIconConsent == .declined)
        #expect(preferences.installID != installID)
    }
}
