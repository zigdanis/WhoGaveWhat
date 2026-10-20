import Foundation
import Testing

@testable import WhoGaveWhat

struct SupportedCurrencyTests {
    @Test func storedSupportedCodeWins() {
        #expect(SupportedCurrency.resolve(stored: "RUB", localeCurrency: "USD") == .rub)
        #expect(SupportedCurrency.resolve(stored: "USD", localeCurrency: "RUB") == .usd)
    }

    @Test func storedUnsupportedCodeBecomesDollars() {
        #expect(SupportedCurrency.resolve(stored: "EUR", localeCurrency: "RUB") == .usd)
        #expect(SupportedCurrency.resolve(stored: "rub", localeCurrency: "RUB") == .usd)
    }

    @Test func missingStoredCodeFollowsTheLocale() {
        #expect(SupportedCurrency.resolve(stored: nil, localeCurrency: "RUB") == .rub)
        #expect(SupportedCurrency.resolve(stored: "", localeCurrency: "RUB") == .rub)
        #expect(SupportedCurrency.resolve(stored: nil, localeCurrency: "EUR") == .usd)
        #expect(SupportedCurrency.resolve(stored: nil, localeCurrency: nil) == .usd)
    }

    @Test func offersOnlyRublesAndDollars() {
        #expect(SupportedCurrency.allCases.map(\.code) == ["RUB", "USD"])
    }
}

struct GiftPriceBucketsTests {
    @Test(arguments: SupportedCurrency.allCases)
    func bucketsAreIncreasingRoundSteps(_ currency: SupportedCurrency) {
        let buckets = GiftPriceBuckets.buckets(for: currency)
        #expect(buckets == buckets.sorted())
        #expect(Set(buckets).count == buckets.count)
        #expect(buckets.count == 15)
    }

    @Test(arguments: SupportedCurrency.allCases)
    func everyBucketSnapsToItself(_ currency: SupportedCurrency) {
        for bucket in GiftPriceBuckets.buckets(for: currency) {
            #expect(GiftPriceBuckets.snap(Double(bucket), currency: currency) == bucket)
        }
    }

    @Test func snapsToTheNearestBucketInLogSpace() {
        // The midpoint between 3 000 and 5 000 is about 3 873, not the arithmetic 4 000.
        #expect(GiftPriceBuckets.snap(3_800, currency: .rub) == 3_000)
        #expect(GiftPriceBuckets.snap(3_900, currency: .rub) == 5_000)
        #expect(GiftPriceBuckets.snap(4_000, currency: .rub) == 5_000)
        #expect(GiftPriceBuckets.snap(120, currency: .usd) == 100)
        #expect(GiftPriceBuckets.snap(125, currency: .usd) == 150)
    }

    @Test func clampsToTheEnds() {
        #expect(GiftPriceBuckets.snap(1, currency: .rub) == 300)
        #expect(GiftPriceBuckets.snap(5_000_000, currency: .rub) == 1_000_000)
        #expect(GiftPriceBuckets.snap(1, currency: .usd) == 5)
        #expect(GiftPriceBuckets.snap(1_000_000, currency: .usd) == 20_000)
    }

    @Test func hasNoBucketForNonPositiveOrNonFiniteValues() {
        for value in [0, -1, -5_000, Double.nan, .infinity, -.infinity] {
            #expect(GiftPriceBuckets.snap(value, currency: .rub) == nil)
        }
    }
}

@MainActor
struct PriceEstimateStateTests {
    private func makeState(
        _ gateway: ScriptedIntelligenceGateway,
        route: GiftSheetRoute = .create,
        currency: String = "RUB",
        composition existing: AppComposition? = nil
    ) throws -> (AddGiftState, AppComposition) {
        let composition = try existing ?? makeTestComposition()
        let preferences = TestPreferencesGateway()
        preferences.setCurrencyCode(currency)
        let state = AddGiftState(
            route: route,
            data: composition.data,
            suggestGift: SuggestGiftUseCase(intelligenceGateway: gateway),
            preferences: preferences,
            debounce: .milliseconds(5)
        )
        return (state, composition)
    }

    private func guitar(_ value: Int? = 10_000) -> GiftIntelligenceResult {
        GiftIntelligenceResult(emoji: "🎸", value: value)
    }

    @Test func estimatePrefillsWhileTheValueIsUntouched() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["гитара"] = guitar()
        let (state, _) = try makeState(gateway)

        state.setName("гитара")
        await state.suggestionTask?.value

        #expect(gateway.currencies == [.rub])
        #expect(state.draft.estimatedValue == 10_000)
        #expect(state.showsEstimate)
        #expect(state.valueText == "10000")
        #expect(state.effectiveValue == 10_000)
        // Inference never touches the user's own value.
        #expect(state.draft.value == nil)
        #expect(state.draft.valueTouched == false)
    }

    @Test func asksForTheCurrentCurrency() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["guitar"] = guitar(150)
        let (state, _) = try makeState(gateway, currency: "USD")

        state.setName("guitar")
        await state.suggestionTask?.value

        #expect(gateway.currencies == [.usd])
        #expect(state.draft.estimatedValue == 150)
    }

    @Test func aValueTypedBeforeTheAnswerIsNeverOverwritten() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.holdsRequests = true
        gateway.results["гитара"] = guitar()
        let (state, _) = try makeState(gateway)

        state.setName("гитара")
        await gateway.waitForRequests(1)
        state.valueText = "777"
        gateway.releaseRequests()
        await state.suggestionTask?.value

        #expect(state.draft.estimatedValue == nil)
        #expect(state.showsEstimate == false)
        #expect(state.valueText == "777")
        #expect(state.draft.value == 777)
        #expect(state.effectiveValue == 777)
        // The icon is still applied.
        #expect(state.draft.aiEmoji == "🎸")
    }

    @Test func aValueTypedAfterTheAnswerReplacesTheEstimateForGood() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["гитара"] = guitar()
        gateway.results["гитара классическая"] = guitar(20_000)
        let (state, _) = try makeState(gateway)
        state.setName("гитара")
        await state.suggestionTask?.value
        #expect(state.valueText == "10000")

        state.valueText = "1200"
        #expect(state.showsEstimate == false)
        #expect(state.valueText == "1200")

        // A later answer for a new name cannot bring the estimate back.
        state.setName("гитара классическая")
        await state.suggestionTask?.value
        #expect(state.valueText == "1200")
        #expect(state.draft.value == 1_200)
        #expect(state.effectiveValue == 1_200)
    }

    @Test func clearingTheFieldKeepsTheUsersEmptyValue() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["гитара"] = guitar()
        let (state, _) = try makeState(gateway)
        state.setName("гитара")
        await state.suggestionTask?.value

        state.valueText = ""

        #expect(state.valueText.isEmpty)
        #expect(state.effectiveValue == nil)
        #expect(state.input.valueTouched)
    }

    @Test func staleEstimateIsClearedWhenTheNextAnswerHasNoPrice() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["гитара"] = guitar()
        gateway.results["что-то"] = GiftIntelligenceResult(emoji: "🎁", value: nil)
        let (state, _) = try makeState(gateway)
        state.setName("гитара")
        await state.suggestionTask?.value
        #expect(state.draft.estimatedValue == 10_000)

        state.setName("что-то")
        await state.suggestionTask?.value
        #expect(state.draft.estimatedValue == nil)

        state.setName("гитара")
        await state.suggestionTask?.value
        #expect(state.draft.estimatedValue == 10_000)
        state.setName("нет ответа")
        await state.suggestionTask?.value
        #expect(state.draft.estimatedValue == nil)
    }

    @Test func renamingDropsTheEstimateBeforeTheNewAnswerArrives() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["гитара"] = guitar()
        gateway.results["носки"] = GiftIntelligenceResult(emoji: "🧦", value: 500)
        let (state, composition) = try makeState(gateway)
        let people = composition.data.people.map(\.id)
        state.previewFrom(people[0])
        state.previewTo(people[1])
        state.setName("гитара")
        await state.suggestionTask?.value
        #expect(state.input.estimatedValue == 10_000)

        gateway.holdsRequests = true
        state.setName("носки")
        #expect(state.input.estimatedValue == nil)
        #expect(state.showsEstimate == false)
        composition.saveGift(state.input)
        #expect(composition.data.gifts.first { $0.name == "носки" }?.value == 0)

        await gateway.waitForRequests(2)
        gateway.holdsRequests = false
        gateway.releaseRequests()
        await state.suggestionTask?.value
        #expect(state.input.estimatedValue == 500)

        // Trailing whitespace is the same name and keeps its estimate.
        state.setName("носки ")
        #expect(state.input.estimatedValue == 500)
    }

    @Test func aHandPickedEmojiStillGetsAnEstimate() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.holdsRequests = true
        gateway.results["гитара"] = guitar()
        gateway.results["гитара классическая"] = guitar(20_000)
        let (state, _) = try makeState(gateway)

        state.setName("гитара")
        await gateway.waitForRequests(1)
        state.selectEmoji("🎻")
        #expect(state.aiLoading == false)
        gateway.releaseRequests()
        await state.suggestionTask?.value
        #expect(state.effectiveEmoji == "🎻")
        #expect(state.draft.aiEmoji == nil)
        #expect(state.draft.estimatedValue == 10_000)

        gateway.holdsRequests = false
        state.setName("гитара классическая")
        await state.suggestionTask?.value
        #expect(state.effectiveEmoji == "🎻")
        #expect(state.draft.estimatedValue == 20_000)
        #expect(state.aiLoading == false)
    }

    @Test func aHandPickedEmojiAndATypedValueNeedNoRequest() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["гитара"] = guitar()
        let (state, _) = try makeState(gateway)
        state.selectEmoji("🎻")
        state.valueText = "3000"

        state.setName("гитара")
        await state.suggestionTask?.value

        #expect(state.suggestionTask == nil)
        #expect(gateway.requests.isEmpty)
        #expect(state.effectiveValue == 3_000)
    }

    @Test func shorteningTheNameBelowTwoCharactersClearsTheEstimate() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["гитара"] = guitar()
        let (state, _) = try makeState(gateway)
        state.setName("гитара")
        await state.suggestionTask?.value
        #expect(state.draft.estimatedValue == 10_000)

        state.setName("г")

        #expect(state.draft.estimatedValue == nil)
        #expect(state.showsEstimate == false)
        #expect(state.valueText.isEmpty)
    }

    @Test func anAnswerWithoutAnEmojiStillGivesThePrice() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["bouquet"] = GiftIntelligenceResult(emoji: nil, value: 3_000)
        let (state, _) = try makeState(gateway)

        state.setName("bouquet")
        await state.suggestionTask?.value

        #expect(state.draft.estimatedValue == 3_000)
        #expect(state.draft.aiEmoji == nil)
        #expect(state.effectiveEmoji == "💐")
    }

    @Test func savingUsesTheEstimateUntilTheUserEditsTheValue() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["гитара"] = guitar()
        let (state, composition) = try makeState(gateway)
        let people = composition.data.people.map(\.id)
        state.setName("гитара")
        state.previewFrom(people[0])
        state.previewTo(people[1])
        await state.suggestionTask?.value

        composition.saveGift(state.input)
        let saved = try #require(composition.data.gifts.first { $0.name == "гитара" })
        #expect(saved.value == 10_000)
    }

    @Test func untouchedEstimateIsSavedAsTheGiftValue() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        var input = makeGiftInput(name: "Guitar", fromID: "you", toID: "igor")
        input.estimatedValue = 10_000

        _ = try? useCase.execute(input)

        #expect(gateway.gifts.first?.value == 10_000)
    }

    @Test func theUsersValueBeatsTheEstimateEvenWhenEmpty() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        var input = makeGiftInput(name: "Guitar", fromID: "you", toID: "igor", value: 2_500, valueTouched: true)
        input.estimatedValue = 10_000
        _ = try? useCase.execute(input)

        var cleared = makeGiftInput(name: "Violin", fromID: "you", toID: "igor", value: nil, valueTouched: true)
        cleared.estimatedValue = 10_000
        _ = try? useCase.execute(cleared)

        #expect(gateway.gifts.first { $0.name == "Guitar" }?.value == 2_500)
        #expect(gateway.gifts.first { $0.name == "Violin" }?.value == 0)
    }

    @Test func editingKeepsTheSavedValueAndIsNeverPrefilled() async throws {
        let gateway = ScriptedIntelligenceGateway()
        let composition = try makeTestComposition()
        let gift = try #require(composition.data.gifts.first)
        let renamed = gift.name + " set"
        gateway.results[renamed] = guitar(99_000)
        let (state, _) = try makeState(gateway, route: .edit(giftID: gift.id), composition: composition)
        #expect(state.draft.valueTouched)
        #expect(state.draft.value == Int(gift.value))

        state.setName(renamed)
        await state.suggestionTask?.value

        #expect(gateway.requests == [renamed])
        #expect(state.draft.estimatedValue == nil)
        #expect(state.showsEstimate == false)
        #expect(state.draft.value == Int(gift.value))
    }
}
