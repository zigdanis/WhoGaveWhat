import Testing

@testable import WhoGaveWhat

@MainActor
final class ScriptedIntelligenceGateway: GiftIntelligenceGateway {
    var isAvailable = true
    var holdsRequests = false
    var results: [String: GiftIntelligenceResult] = [:]
    private(set) var requests: [String] = []
    private(set) var currencies: [SupportedCurrency] = []
    private(set) var prewarmCount = 0
    private var pending: [CheckedContinuation<Void, Never>] = []

    func prewarm() { prewarmCount += 1 }

    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult? {
        requests.append(name)
        currencies.append(currency)
        if holdsRequests {
            await withCheckedContinuation { pending.append($0) }
        }
        return results[name]
    }

    func releaseRequests() {
        let waiting = pending
        pending = []
        waiting.forEach { $0.resume() }
    }

    func waitForRequests(_ count: Int) async {
        for _ in 0..<500 where requests.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
struct GiftEmojiInferenceTests {
    private func makeState(
        _ gateway: ScriptedIntelligenceGateway,
        route: GiftSheetRoute = .create
    ) throws -> AddGiftState {
        let composition = try makeTestComposition()
        return AddGiftState(
            route: route,
            data: composition.data,
            suggestGift: SuggestGiftUseCase(intelligenceGateway: gateway),
            debounce: .milliseconds(5)
        )
    }

    private func result(_ emoji: String) -> GiftIntelligenceResult {
        GiftIntelligenceResult(emoji: emoji, value: 1_000)
    }

    @Test func showsHeuristicImmediatelyThenModelEmoji() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["bouquet"] = result("🌷")
        let state = try makeState(gateway)

        state.setName("bouquet")
        #expect(state.effectiveEmoji == "💐")

        await state.suggestionTask?.value
        #expect(state.effectiveEmoji == "🌷")
        #expect(state.aiLoading == false)
    }

    @Test func fallsBackToHeuristicWhenModelHasNoAnswer() async throws {
        let gateway = ScriptedIntelligenceGateway()
        let state = try makeState(gateway)

        state.setName("bouquet")
        await state.suggestionTask?.value

        #expect(gateway.requests == ["bouquet"])
        #expect(state.effectiveEmoji == "💐")
        #expect(state.aiLoading == false)
    }

    @Test func manualEmojiBeatsModelAndSurvivesRenaming() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["bouquet"] = result("🌷")
        let state = try makeState(gateway)
        state.setName("bouquet")
        await state.suggestionTask?.value

        state.selectEmoji("🐶")
        #expect(state.effectiveEmoji == "🐶")

        state.setName("bouquet of roses")
        await state.suggestionTask?.value
        #expect(state.effectiveEmoji == "🐶")
        #expect(state.input.emoji == "🐶")
        #expect(gateway.requests == ["bouquet"])
    }

    @Test func debounceSendsOnlyTheLatestName() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["bouquet"] = result("🌷")
        let state = try makeState(gateway)

        state.setName("bo")
        state.setName("bouq")
        state.setName("bouquet")
        await state.suggestionTask?.value

        #expect(gateway.requests == ["bouquet"])
        #expect(state.effectiveEmoji == "🌷")
    }

    @Test func staleInFlightResultIsDiscarded() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.holdsRequests = true
        gateway.results["bouquet"] = result("🌷")
        gateway.results["wine"] = result("🥂")
        let state = try makeState(gateway)

        state.setName("bouquet")
        await gateway.waitForRequests(1)
        let first = state.suggestionTask
        state.setName("wine")
        gateway.releaseRequests()
        await first?.value
        #expect(state.draft.aiEmoji == nil)
        #expect(state.effectiveEmoji == "🍷")

        await gateway.waitForRequests(2)
        gateway.releaseRequests()
        await state.suggestionTask?.value
        #expect(gateway.requests == ["bouquet", "wine"])
        #expect(state.effectiveEmoji == "🥂")
        #expect(state.aiLoading == false)
    }

    @Test func cancelAndShortNamesNeverReachTheModel() async throws {
        let gateway = ScriptedIntelligenceGateway()
        let state = try makeState(gateway)

        state.setName("a")
        #expect(state.suggestionTask == nil)

        state.setName("bouquet")
        let task = state.suggestionTask
        state.cancel()
        await task?.value
        #expect(gateway.requests.isEmpty)
        #expect(state.aiLoading == false)
    }

    @Test func unavailableModelKeepsHeuristic() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.isAvailable = false
        let state = try makeState(gateway)

        state.setName("bouquet")
        await state.suggestionTask?.value

        #expect(gateway.requests.isEmpty)
        #expect(state.effectiveEmoji == "💐")
        state.prewarm()
        #expect(gateway.prewarmCount == 0)
    }

    @Test func prewarmsWhenModelIsAvailable() throws {
        let gateway = ScriptedIntelligenceGateway()
        let state = try makeState(gateway)
        state.prewarm()
        #expect(gateway.prewarmCount == 1)
    }

    @Test func editingKeepsStoredEmojiUntilRenamed() async throws {
        let gateway = ScriptedIntelligenceGateway()
        let composition = try makeTestComposition()
        let gift = try #require(composition.data.gifts.first)
        let renamed = gift.name + " set"
        gateway.results[renamed] = result("🧩")
        let state = AddGiftState(
            route: .edit(giftID: gift.id),
            data: composition.data,
            suggestGift: SuggestGiftUseCase(intelligenceGateway: gateway),
            debounce: .milliseconds(5)
        )
        #expect(state.effectiveEmoji == gift.emoji)
        #expect(state.input.emoji == nil)

        state.setName(gift.name)
        #expect(gateway.requests.isEmpty)

        state.setName(renamed)
        await state.suggestionTask?.value
        #expect(gateway.requests == [renamed])
        #expect(state.effectiveEmoji == "🧩")
    }

    @Test func manuallyPickedEmojiSurvivesSaveReopenAndRename() async throws {
        let composition = try makeTestComposition()
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["Bouquet fixed"] = result("🌷")
        let suggest = SuggestGiftUseCase(intelligenceGateway: gateway)
        let people = composition.data.people.map(\.id)
        let creating = AddGiftState(route: .create, data: composition.data, suggestGift: suggest, debounce: .milliseconds(5))
        creating.setName("Bouquet")
        creating.previewFrom(people[0])
        creating.previewTo(people[1])
        creating.selectEmoji("🐶")
        composition.saveGift(creating.input)

        let saved = try #require(composition.data.gifts.first { $0.name == "Bouquet" })
        #expect(saved.emoji == "🐶")
        #expect(saved.emojiPickedByUser)

        let editing = AddGiftState(route: .edit(giftID: saved.id), data: composition.data, suggestGift: suggest, debounce: .milliseconds(5))
        #expect(editing.input.emoji == "🐶")
        editing.setName("Bouquet fixed")
        await editing.suggestionTask?.value
        #expect(editing.effectiveEmoji == "🐶")
        #expect(gateway.requests.isEmpty)
    }

    @Test func inferredEmojiIsRevisedWhenRenamingAfterReopen() async throws {
        let composition = try makeTestComposition()
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["Bouquet fixed"] = result("🌷")
        let suggest = SuggestGiftUseCase(intelligenceGateway: gateway)
        let people = composition.data.people.map(\.id)
        let creating = AddGiftState(route: .create, data: composition.data, suggestGift: suggest, debounce: .milliseconds(5))
        creating.setName("Bouquet")
        creating.previewFrom(people[0])
        creating.previewTo(people[1])
        composition.saveGift(creating.input)

        let saved = try #require(composition.data.gifts.first { $0.name == "Bouquet" })
        #expect(saved.emojiPickedByUser == false)

        let editing = AddGiftState(route: .edit(giftID: saved.id), data: composition.data, suggestGift: suggest, debounce: .milliseconds(5))
        editing.setName("Bouquet fixed")
        await editing.suggestionTask?.value
        #expect(editing.effectiveEmoji == "🌷")
    }

    @Test func renamingKeepsStoredEmojiWhenNothingBetterIsKnown() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.isAvailable = false
        let composition = try makeTestComposition()
        let gift = try #require(composition.data.gifts.first { $0.emoji != "🎁" && $0.emoji != "🍷" })
        let state = AddGiftState(
            route: .edit(giftID: gift.id),
            data: composition.data,
            suggestGift: SuggestGiftUseCase(intelligenceGateway: gateway),
            debounce: .milliseconds(5)
        )

        state.setName("zzz unknown thing")
        #expect(state.effectiveEmoji == gift.emoji)
        #expect(state.input.aiEmoji == gift.emoji)

        state.setName("red wine")
        #expect(state.effectiveEmoji == "🍷")
    }
}

struct GiftEmojiValidationTests {
    @Test func acceptsSingleEmojiGraphemes() {
        for emoji in [
            "🎁", "💐", "🕯️", "❤️", "🧑‍🍳", "👍🏽", "🇷🇺", "⌚", "☝🏽", "1️⃣", "#️⃣", "©️", "®️", "™️", "▶️", "👁‍🗨"
        ] {
            #expect(GiftEmoji.validated(emoji) == emoji, "\(emoji)")
        }
        #expect(GiftEmoji.validated("  🎧\n") == "🎧")
    }

    @Test func rejectsTextAndMultipleEmoji() {
        for text in [
            "", "  ", "a", "Я", "7", "#", "*", "©", "®", "™", "‼", "↔", "▶", "❤", "🏻", "🇦", "a\u{FE0F}", "1\u{FE0F}",
            "gift", "🎁🎁", "🎁 x", "букет"
        ] {
            #expect(GiftEmoji.validated(text) == nil, "\(text)")
        }
    }
}
