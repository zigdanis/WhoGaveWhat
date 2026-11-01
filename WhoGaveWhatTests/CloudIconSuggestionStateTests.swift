import Testing

@testable import WhoGaveWhat

@MainActor
struct CloudIconSuggestionStateTests {
    private func makeState(
        preferences: TestPreferencesGateway,
        cloud: ScriptedIntelligenceGateway,
        onDevice: GiftIntelligenceGateway = TestIntelligenceGateway(),
        analytics: AnalyticsGateway = NoopAnalyticsGateway(),
        data: AppData
    ) -> AddGiftState {
        let intelligence = PreferredGiftIntelligenceGateway(cloud: cloud, onDevice: onDevice)
        return AddGiftState(
            route: .create,
            data: data,
            suggestGift: SuggestGiftUseCase(intelligenceGateway: intelligence),
            preferences: preferences,
            debounce: .milliseconds(5),
            analytics: analytics
        )
    }

    @Test func firstGiftNameGoesToTheCloudWithoutAnyPrompt() async throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        let cloud = ScriptedIntelligenceGateway()
        cloud.results["гитара"] = GiftIntelligenceResult(emoji: "🎸", value: nil)
        let state = makeState(preferences: preferences, cloud: cloud, data: composition.data)

        state.setName("гитара")
        await state.suggestionTask?.value

        #expect(cloud.requests == ["гитара"])
        #expect(state.draft.aiEmoji == "🎸")
        #expect(state.effectiveEmoji == "🎸")
        #expect(state.draft.value == nil)
        #expect(state.draft.valueTouched == false)
    }

    @Test func tooShortNamesAreNotSent() throws {
        let composition = try makeTestComposition()
        let cloud = ScriptedIntelligenceGateway()
        let state = makeState(preferences: TestPreferencesGateway(), cloud: cloud, data: composition.data)

        state.setName("  я \n")

        #expect(state.suggestionTask == nil)
        #expect(cloud.requests.isEmpty)
    }

    @Test func suggestionAnalyticsNameTheServiceThatAnswered() async throws {
        let composition = try makeTestComposition()
        let analytics = RecordingAnalyticsGateway()
        let cloud = ScriptedIntelligenceGateway()
        cloud.results["гитара"] = GiftIntelligenceResult(emoji: "🎸", value: nil)
        let onDevice = ScriptedIntelligenceGateway()
        onDevice.results["кроссовки"] = GiftIntelligenceResult(emoji: "👟", value: 5_000)
        let state = makeState(
            preferences: TestPreferencesGateway(), cloud: cloud, onDevice: onDevice, analytics: analytics, data: composition.data)

        state.setName("гитара")
        await state.suggestionTask?.value
        state.setName("кроссовки")
        await state.suggestionTask?.value

        let providers = analytics.events.compactMap { event -> SuggestionProvider? in
            if case .giftSuggestionCompleted(let provider, _, _, _) = event { provider } else { nil }
        }
        #expect(providers == [.cloud, .onDevice])
        #expect(state.draft.aiEmoji == "👟")
        #expect(state.draft.estimatedValue == 5_000)
    }

    @Test func manualPickBeatsLateCloudAnswer() async throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        let cloud = ScriptedIntelligenceGateway()
        cloud.holdsRequests = true
        cloud.results["гитара"] = GiftIntelligenceResult(emoji: "🎸", value: nil)
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
    }

    @Test func staleCloudAnswerCannotReplaceLatestName() async throws {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        let cloud = ScriptedIntelligenceGateway()
        cloud.holdsRequests = true
        cloud.results["гитара"] = GiftIntelligenceResult(emoji: "🎸", value: nil)
        cloud.results["кроссовки"] = GiftIntelligenceResult(emoji: "👟", value: nil)
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
        let cloud = ScriptedIntelligenceGateway()
        let gateway = PreferredGiftIntelligenceGateway(cloud: cloud, onDevice: TestIntelligenceGateway())
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
}
