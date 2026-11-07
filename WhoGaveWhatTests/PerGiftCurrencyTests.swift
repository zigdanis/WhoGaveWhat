import Foundation
import SwiftData
import Testing

@testable import WhoGaveWhat

/// The store App Store 1.0-1.2.0 wrote, from `Fixtures/StoreFixtures` (see `StoreFixtureMigrationTests`).
private var fixture120: StoreFixtures.Fixture {
    get throws {
        try #require(StoreFixtures.manifest.fixtures.first { $0.file == "StoreFixture-1.2.0.store" })
    }
}

/// A copy of the 1.2.0 store in its own temporary folder, because opening a store migrates it in place.
private func copyOf120Store() throws -> URL {
    let folder = try makeTemporaryDirectory()
    let url = folder.appending(path: "\(SwiftDataStore.storeName).store")
    try FileManager.default.copyItem(at: try StoreFixtures.url(of: try fixture120), to: url)
    return url
}

/// Removes the temporary folder `copyOf120Store` made.
private func removeCopy(_ url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

/// A throwaway defaults suite holding `preference`, removed again by `remove`.
private func defaultsSuite(preferring preference: SupportedCurrency) throws -> (UserDefaults, remove: () -> Void) {
    let name = "LegacyStoreMigrationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.set(preference.code, forKey: "preferredCurrencyCode")
    return (defaults, { defaults.removePersistentDomain(forName: name) })
}

/// How many gifts the fixture dataset holds.
private var fixtureGiftCount: Int { StoreFixtures.manifest.dataset.gifts.count }

@MainActor
struct LegacyStoreMigrationTests {
    /// Gifts from 1.2.0 were shown in the currency preference, so opening the app's store through the
    /// preferences gives them that currency and keeps every other field.
    @Test(arguments: SupportedCurrency.allCases)
    func giftsFrom120TakeThePreferenceTheyWereShownIn(_ preference: SupportedCurrency) throws {
        let url = try copyOf120Store()
        defer { removeCopy(url) }
        let (defaults, removeDefaults) = try defaultsSuite(preferring: preference)
        defer { removeDefaults() }

        let store = try SwiftDataStore.openPersistent(
            at: url, preferences: UserDefaultsPreferencesGateway(defaults: defaults))
        let gifts = try SwiftDataGiftGateway(context: store.context).loadGifts().sorted { $0.id < $1.id }
        let people = try SwiftDataPeopleGateway(context: store.context).loadPeople().people

        #expect(gifts == StoreFixtures.expectedGifts(for: try fixture120, legacyCurrency: preference))
        #expect(gifts.allSatisfy { $0.currency == preference })
        #expect(people == StoreFixtures.expectedPeople(for: try fixture120))
    }

    @Test func theMigratedCurrencyIsStoredOnceAndLaterPreferencesDoNotChangeIt() throws {
        let url = try copyOf120Store()
        defer { removeCopy(url) }
        let preferences = TestPreferencesGateway()
        preferences.setCurrencyCode("RUB")
        do {
            let store = try SwiftDataStore.openPersistent(at: url, preferences: preferences)
            #expect(try SwiftDataGiftGateway(context: store.context).loadGifts().allSatisfy { $0.currency == .rub })
        }

        preferences.setCurrencyCode("USD")
        let reopened = try SwiftDataStore.openPersistent(at: url, preferences: preferences)

        #expect(try reopened.assignLegacyGiftCurrency(.usd) == 0)
        #expect(try SwiftDataGiftGateway(context: reopened.context).loadGifts().allSatisfy { $0.currency == .rub })
    }

    @Test func aMigratedStoreKeepsNewGiftsInTheirOwnCurrency() throws {
        let url = try copyOf120Store()
        defer { removeCopy(url) }
        let preferences = TestPreferencesGateway()
        preferences.setCurrencyCode("RUB")
        let composition = AppComposition(
            store: try SwiftDataStore.openPersistent(at: url, preferences: preferences),
            preferences: preferences,
            intelligence: TestIntelligenceGateway())

        #expect(
            composition.saveGift(
                makeGiftInput(
                    name: "Gloves", fromID: "p-anna", toID: "p-mark", value: 40, valueTouched: true, currency: .usd)) == .saved)

        let byName = Dictionary(uniqueKeysWithValues: composition.data.gifts.map { ($0.name, $0) })
        #expect(byName["Gloves"]?.currency == .usd)
        #expect(byName["Wool scarf"]?.currency == .rub)
        #expect(byName["Concert tickets"]?.currency == .rub)
        #expect(composition.data.gifts.count == fixtureGiftCount + 1)
    }

    /// Without a currency to give them, gifts from an old store fail to load instead of taking a guessed one.
    @Test func legacyGiftsWithoutAKnownCurrencyAreNeverGuessed() throws {
        let url = try copyOf120Store()
        defer { removeCopy(url) }
        let store = try SwiftDataStore(url: url)

        #expect(throws: SwiftDataPersistenceError.self) {
            try SwiftDataGiftGateway(context: store.context).loadGifts()
        }
        #expect(try store.assignLegacyGiftCurrency(.usd) == fixtureGiftCount)
        #expect(try SwiftDataGiftGateway(context: store.context).loadGifts().allSatisfy { $0.currency == .usd })
    }

    /// If storing the currency failed at open, the gifts still show in the currency they were going
    /// to get, and the next open stores it.
    @Test func legacyGiftsShowInTheMigrationCurrencyUntilItIsStored() throws {
        let url = try copyOf120Store()
        defer { removeCopy(url) }
        let unmigrated = try SwiftDataStore(url: url)

        let gifts = try SwiftDataGiftGateway(context: unmigrated.context, legacyGiftCurrency: .rub).loadGifts()

        #expect(gifts.count == fixtureGiftCount)
        #expect(gifts.allSatisfy { $0.currency == .rub })
        #expect(unmigrated.legacyGiftCurrencyError == nil)
        // An unknown stored code is never replaced by the legacy currency.
        let stored = try #require(try unmigrated.context.fetch(FetchDescriptor<StoredGift>()).first)
        stored.currencyCode = "EUR"
        #expect(throws: SwiftDataPersistenceError.missingCurrency(giftID: stored.id)) {
            try SwiftDataGiftGateway(context: unmigrated.context, legacyGiftCurrency: .rub).loadGifts()
        }
    }

    /// A failed save of the migration never stops the app: the failure is reported, the gifts show in
    /// the migration currency, and the next open stores that currency even if the default changed.
    @Test func aFailedMigrationSaveKeepsTheJournalAndIsRetriedOnTheNextOpen() throws {
        struct DiskFull: Error {}
        let url = try copyOf120Store()
        defer { removeCopy(url) }
        let preferences = TestPreferencesGateway()
        preferences.setCurrencyCode("RUB")
        let analytics = RecordingAnalyticsGateway()

        let failing = try SwiftDataStore(
            url: url, legacyGiftCurrency: preferences.legacyGiftCurrency,
            saveLegacyGiftCurrency: { _ in throw DiskFull() })
        let composition = AppComposition(
            store: failing, preferences: preferences, intelligence: TestIntelligenceGateway(), analytics: analytics)

        #expect(failing.legacyGiftCurrencyError is DiskFull)
        #expect(analytics.failures.map(\.operation).contains("migrate_gift_currency"))
        #expect(composition.data.gifts.count == fixtureGiftCount)
        #expect(composition.data.gifts.allSatisfy { $0.currency == .rub })
        let unsaved = try failing.context.fetch(FetchDescriptor<StoredGift>(predicate: #Predicate { $0.currencyCode == nil }))
        #expect(unsaved.count == fixtureGiftCount)

        composition.setDefaultCurrency(.usd)
        let reopened = try SwiftDataStore.openPersistent(at: url, preferences: preferences)

        #expect(reopened.legacyGiftCurrencyError == nil)
        #expect(try reopened.assignLegacyGiftCurrency(.usd) == 0)
        #expect(try SwiftDataGiftGateway(context: reopened.context).loadGifts().allSatisfy { $0.currency == .rub })
    }

    /// The migration currency is fixed the first time it is read, so changing the default currency
    /// before the migration is stored (for example after a failed save) cannot relabel old gifts.
    @Test func theLegacyCurrencyIsPinnedOnFirstRead() throws {
        let (defaults, removeDefaults) = try defaultsSuite(preferring: .rub)
        defer { removeDefaults() }
        let preferences = UserDefaultsPreferencesGateway(defaults: defaults)

        #expect(preferences.legacyGiftCurrency == .rub)
        preferences.setCurrencyCode("USD")

        #expect(preferences.defaultCurrency == .usd)
        #expect(preferences.legacyGiftCurrency == .rub)
        #expect(UserDefaultsPreferencesGateway(defaults: defaults).legacyGiftCurrency == .rub)
    }
}

@MainActor
struct PerGiftCurrencyTests {
    /// An empty journal with two people and USD as the default currency.
    private func makeComposition(
        analytics: AnalyticsGateway = NoopAnalyticsGateway()
    ) throws -> (AppComposition, TestPreferencesGateway) {
        let preferences = TestPreferencesGateway()
        preferences.setCurrencyCode("USD")
        preferences.selfPersonID = "me"
        let store = try SwiftDataStore(inMemory: true)
        let people = SwiftDataPeopleGateway(context: store.context)
        try people.createPerson(id: "me", name: "Me", colorHex: 0x12161C, sortIndex: 0)
        try people.createPerson(id: "kim", name: "Kim", colorHex: 0x12805C, sortIndex: 1)
        let composition = AppComposition(
            store: store, preferences: preferences, intelligence: TestIntelligenceGateway(), analytics: analytics)
        return (composition, preferences)
    }

    /// Fills the Add gift form as a user would and saves it.
    @discardableResult
    private func addGift(
        _ name: String, value: String, in composition: AppComposition, from: String = "kim", to: String = "me",
        currency: SupportedCurrency? = nil
    ) -> Bool {
        let state = AddGiftState(
            route: .create, data: composition.data, suggestGift: composition.suggestGift,
            preferences: composition.preferences)
        state.setName(name)
        state.previewFrom(from)
        state.previewTo(to)
        state.valueText = value
        if let currency { state.currency = currency }
        return composition.saveGift(state.input) == .saved
    }

    private func gift(named name: String, in composition: AppComposition) throws -> Gift {
        try #require(composition.data.gifts.first { $0.name == name })
    }

    @Test func dollarsThenRublesGiveSeparateTotalsAndNoMixedSum() throws {
        let (composition, _) = try makeComposition()

        #expect(addGift("Headphones", value: "100", in: composition))
        composition.setDefaultCurrency(.rub)
        #expect(addGift("Cake", value: "100", in: composition))

        #expect(try gift(named: "Headphones", in: composition).currency == .usd)
        #expect(try gift(named: "Cake", in: composition).currency == .rub)
        let both = CurrencyAmounts([.usd: 100, .rub: 100])
        #expect(composition.data.gifts.totals == both)

        let year = Calendar.current.component(.year, from: AppDate.today)
        let summary = composition.buildInsights.summary(gifts: composition.data.gifts, relativeTo: "me", year: year)
        #expect(summary.circulatedValue == both)
        #expect(summary.receivedValue == both)
        #expect(summary.net == both)
        let balance = try #require(
            composition.buildInsights.balances(
                gifts: composition.data.gifts, people: composition.data.people, relativeTo: "me", year: year
            ).first)
        #expect(balance.net == both)
        let comparison = composition.buildInsights.comparison(
            gifts: composition.data.gifts, a: composition.data.people[0], b: composition.data.people[1], year: year)
        #expect(comparison.comparableValues == nil)
        let month = try #require(
            composition.buildTimeline.execute(gifts: composition.data.gifts, filter: "all", relativeTo: "me").first)
        #expect(month.total == both)

        let locale = Locale(identifier: "en_US")
        let shown = formattedAmounts(both, preferred: composition.defaultCurrency, locale: locale)
        let rubles = formattedCurrency(100, code: "RUB", locale: locale)
        let dollars = formattedCurrency(100, code: "USD", locale: locale)
        #expect(shown == "\(rubles) · \(dollars)")
        #expect(!shown.contains("200"))
    }

    @Test func editingAGiftChangesOnlyThatGiftsCurrencyAndKeepsTheNumber() throws {
        let (composition, _) = try makeComposition()
        addGift("Headphones", value: "100", in: composition)
        addGift("Book", value: "30", in: composition)
        let headphones = try gift(named: "Headphones", in: composition)

        let state = AddGiftState(
            route: .edit(giftID: headphones.id), data: composition.data, suggestGift: composition.suggestGift,
            preferences: composition.preferences)
        #expect(state.currency == .usd)
        state.currency = .rub
        #expect(state.valueText == "100")
        #expect(state.suggestionTask == nil)
        #expect(composition.saveGift(state.input) == .saved)

        let edited = try gift(named: "Headphones", in: composition)
        #expect(edited.id == headphones.id)
        #expect(edited.value == 100)
        #expect(edited.currency == .rub)
        #expect(edited.createdAt == headphones.createdAt)
        #expect(try gift(named: "Book", in: composition).currency == .usd)
        #expect(composition.defaultCurrency == .usd)
    }

    @Test func anEditedGiftOpensInItsOwnCurrencyNotTheDefault() throws {
        let (composition, _) = try makeComposition()
        addGift("Headphones", value: "100", in: composition)
        composition.setDefaultCurrency(.rub)
        let headphones = try gift(named: "Headphones", in: composition)

        let editing = AddGiftState(
            route: .edit(giftID: headphones.id), data: composition.data, suggestGift: composition.suggestGift,
            preferences: composition.preferences)
        let creating = AddGiftState(
            route: .create, data: composition.data, suggestGift: composition.suggestGift,
            preferences: composition.preferences)

        #expect(editing.currency == .usd)
        #expect(editing.input.currency == .usd)
        #expect(creating.currency == .rub)
    }

    @Test func changingTheDefaultCurrencyLeavesSavedGiftsUntouched() throws {
        let composition = try makeTestComposition()
        let before = composition.data.gifts
        #expect(before.allSatisfy { $0.currency == .rub })

        composition.setDefaultCurrency(.usd)
        composition.reloadData()

        #expect(composition.data.gifts == before)
        #expect(composition.defaultCurrency == .usd)
        #expect(composition.preferences.currencyCode == "USD")
    }

    @Test func savedGiftAnalyticsNameTheCurrencyButNeverTheAmount() throws {
        let analytics = RecordingAnalyticsGateway()
        let (composition, _) = try makeComposition(analytics: analytics)
        composition.setDefaultCurrency(.rub)

        addGift("Headphones", value: "12345", in: composition, currency: .usd)

        #expect(try gift(named: "Headphones", in: composition).currency == .usd)
        guard case .giftSaved(let properties) = analytics.events.last else {
            Issue.record("No gift_saved event")
            return
        }
        // The gift's own currency, not the default.
        #expect(properties.currency == "USD")
        #expect(AnalyticsEvent.giftSaved(properties).properties["currency"] == .string("USD"))
        let values = AnalyticsEvent.giftSaved(properties).properties.values.map { "\($0)" }
        #expect(!values.contains { $0.contains("12345") })
    }
}

/// Answers each currency with its own price, and only when the test says so, so answers can arrive in any order.
@MainActor
private final class PerCurrencyIntelligenceGateway: GiftIntelligenceGateway {
    var isAvailable = true
    let prices: [SupportedCurrency: Int]
    private(set) var currencies: [SupportedCurrency] = []
    private var waiting: [SupportedCurrency: CheckedContinuation<Void, Never>] = [:]

    init(prices: [SupportedCurrency: Int]) { self.prices = prices }

    func prewarm() {}

    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult? {
        currencies.append(currency)
        await withCheckedContinuation { waiting[currency] = $0 }
        return GiftIntelligenceResult(emoji: "🎸", value: prices[currency])
    }

    func answer(_ currency: SupportedCurrency) {
        waiting.removeValue(forKey: currency)?.resume()
    }

    /// Answers every waiting request, so a failed test leaves nothing suspended.
    func answerAll() {
        let pending = waiting.values
        waiting = [:]
        pending.forEach { $0.resume() }
    }

    /// A request records its currency and starts waiting in the same main-actor step. False when
    /// `count` requests did not arrive in time, so the test can stop instead of awaiting a task forever.
    func waitForRequests(_ count: Int) async -> Bool {
        for _ in 0..<500 where currencies.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return currencies.count >= count
    }
}

@MainActor
struct GiftCurrencyEstimateTests {
    private func makeState(
        _ gateway: ScriptedIntelligenceGateway, defaultCurrency: SupportedCurrency = .rub
    ) throws -> (AddGiftState, AppComposition) {
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        preferences.setCurrencyCode(defaultCurrency.code)
        let state = AddGiftState(
            route: .create, data: composition.data, suggestGift: SuggestGiftUseCase(intelligenceGateway: gateway),
            preferences: preferences, debounce: .milliseconds(5))
        let people = composition.data.people.map(\.id)
        state.previewFrom(people[0])
        state.previewTo(people[1])
        return (state, composition)
    }

    @Test func anEstimateIsSavedInTheCurrencyItWasAskedFor() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["guitar"] = GiftIntelligenceResult(emoji: "🎸", value: 10_000)
        let (state, composition) = try makeState(gateway)

        state.setName("guitar")
        await state.suggestionTask?.value

        #expect(gateway.currencies == [.rub])
        #expect(state.draft.estimatedCurrency == .rub)
        #expect(composition.saveGift(state.input) == .saved)
        let saved = try #require(composition.data.gifts.first { $0.name == "guitar" })
        #expect(saved.value == 10_000)
        #expect(saved.currency == .rub)
    }

    @Test func switchingCurrencyDropsTheEstimateAndAsksAgainInTheNewOne() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["guitar"] = GiftIntelligenceResult(emoji: "🎸", value: 10_000)
        let (state, composition) = try makeState(gateway)
        state.setName("guitar")
        await state.suggestionTask?.value
        #expect(state.draft.estimatedValue == 10_000)

        gateway.results["guitar"] = GiftIntelligenceResult(emoji: "🎸", value: 150)
        state.currency = .usd
        #expect(state.draft.estimatedValue == nil)
        #expect(state.valueText.isEmpty)
        await state.suggestionTask?.value

        #expect(gateway.currencies == [.rub, .usd])
        #expect(state.draft.estimatedValue == 150)
        #expect(state.draft.estimatedCurrency == .usd)
        #expect(composition.saveGift(state.input) == .saved)
        let saved = try #require(composition.data.gifts.first { $0.name == "guitar" })
        #expect(saved.value == 150)
        #expect(saved.currency == .usd)
    }

    @Test func anAnswerForTheCurrencyTheUserLeftIsNeverApplied() async throws {
        let gateway = PerCurrencyIntelligenceGateway(prices: [.rub: 10_000, .usd: 150])
        let composition = try makeTestComposition()
        let preferences = TestPreferencesGateway()
        preferences.setCurrencyCode("RUB")
        let state = AddGiftState(
            route: .create, data: composition.data, suggestGift: SuggestGiftUseCase(intelligenceGateway: gateway),
            preferences: preferences, debounce: .milliseconds(5))
        let people = composition.data.people.map(\.id)
        state.previewFrom(people[0])
        state.previewTo(people[1])
        defer { gateway.answerAll() }
        state.setName("guitar")
        try #require(await gateway.waitForRequests(1))
        let rubleRequest = try #require(state.suggestionTask)

        state.currency = .usd
        try #require(await gateway.waitForRequests(2))
        let dollarRequest = try #require(state.suggestionTask)
        // The new answer arrives first, then the one for the currency the user left.
        gateway.answer(.usd)
        await dollarRequest.value
        #expect(state.draft.estimatedValue == 150)
        gateway.answer(.rub)
        await rubleRequest.value

        #expect(gateway.currencies == [.rub, .usd])
        #expect(state.draft.estimatedValue == 150)
        #expect(state.draft.estimatedCurrency == .usd)
        #expect(composition.saveGift(state.input) == .saved)
        let saved = try #require(composition.data.gifts.first { $0.name == "guitar" })
        #expect(saved.value == 150)
        #expect(saved.currency == .usd)
    }

    @Test func aTypedValueKeepsItsDigitsAndAsksForNothingWhenTheCurrencyChanges() async throws {
        let gateway = ScriptedIntelligenceGateway()
        gateway.results["guitar"] = GiftIntelligenceResult(emoji: "🎸", value: 10_000)
        let (state, composition) = try makeState(gateway)
        state.setName("guitar")
        await state.suggestionTask?.value
        state.valueText = "250"
        let finishedRequest = state.suggestionTask

        state.currency = .usd

        // No new request: the finished one is still the last.
        #expect(state.suggestionTask == finishedRequest)
        #expect(gateway.currencies == [.rub])
        #expect(state.valueText == "250")
        #expect(composition.saveGift(state.input) == .saved)
        let saved = try #require(composition.data.gifts.first { $0.name == "guitar" })
        #expect(saved.value == 250)
        #expect(saved.currency == .usd)
    }

    @Test func theSaveUseCaseKeepsTheEstimatesCurrencyAndTheUsersOtherwise() throws {
        let (useCase, _) = makeSaveGiftUseCase()
        var input = makeGiftInput(name: "Guitar", fromID: "a", toID: "b", currency: .rub)
        input.estimatedValue = 150
        input.estimatedCurrency = .usd

        #expect(try useCase.execute(input)?.currency == .usd)
        #expect(try useCase.execute(input)?.value == 150)

        input.valueTouched = true
        input.value = 9_000
        #expect(try useCase.execute(input)?.currency == .rub)

        input.valueTouched = false
        input.estimatedValue = nil
        #expect(try useCase.execute(input)?.currency == .rub)
        #expect(try useCase.execute(input)?.value == 0)
    }
}

@MainActor
struct GiftCurrencyPersistenceTests {
    @Test func theGatewayRoundTripsEachGiftsCurrency() throws {
        let store = try SwiftDataStore(inMemory: true)
        let people = SwiftDataPeopleGateway(context: store.context)
        try people.createPerson(id: "a", name: "A", colorHex: 0, sortIndex: 0)
        try people.createPerson(id: "b", name: "B", colorHex: 0, sortIndex: 1)
        let gateway = SwiftDataGiftGateway(context: store.context)
        var gift = Gift(
            id: "g", emoji: "🎁", name: "G", giverID: "a", recipientID: "b", paidByYou: false, occasion: "",
            date: AppDate.today, value: 100, currency: .usd, createdAt: AppDate.today)

        try gateway.save(gift)
        #expect(try gateway.loadGifts().first?.currency == .usd)
        gift.currency = .rub
        try gateway.save(gift)
        #expect(try gateway.loadGifts() == [gift])
    }

    @Test func aGiftWithAnUnknownStoredCurrencyFailsToLoad() throws {
        let store = try SwiftDataStore(inMemory: true, seed: true)
        let stored = try #require(try store.context.fetch(FetchDescriptor<StoredGift>()).first)
        stored.currencyCode = "EUR"
        try store.context.save()

        #expect(throws: SwiftDataPersistenceError.missingCurrency(giftID: stored.id)) {
            try SwiftDataGiftGateway(context: store.context).loadGifts()
        }
    }

    @Test(arguments: SupportedCurrency.allCases)
    func sampleGiftsAreInTheSampleCurrency(_ currency: SupportedCurrency) throws {
        let store = try SwiftDataStore(inMemory: true, seed: true, sampleCurrency: currency)
        #expect(try SwiftDataGiftGateway(context: store.context).loadGifts().allSatisfy { $0.currency == currency })
    }
}

struct CurrencyAmountsTests {
    private let en = Locale(identifier: "en_US")

    @Test func keepsEachCurrencySeparate() {
        var amounts = CurrencyAmounts()
        amounts.add(100, in: .usd)
        amounts.add(2_000, in: .rub)
        amounts.add(50, in: .usd)

        #expect(amounts[.usd] == 150)
        #expect(amounts[.rub] == 2_000)
        #expect(amounts.currencies == [.rub, .usd])
    }

    @Test func subtractsCurrencyByCurrency() {
        let received = CurrencyAmounts([.usd: 100])
        let given = CurrencyAmounts([.usd: 40, .rub: 500])

        #expect(received - given == CurrencyAmounts([.usd: 60, .rub: -500]))
    }

    @Test func signNeedsEveryCurrencyToAgree() {
        #expect(CurrencyAmounts().sign == .even)
        #expect(CurrencyAmounts([.usd: 0.4, .rub: -0.3]).sign == .even)
        #expect(CurrencyAmounts([.usd: 10, .rub: 0]).sign == .positive)
        #expect(CurrencyAmounts([.usd: -10, .rub: -5]).sign == .negative)
        #expect(CurrencyAmounts([.usd: 10, .rub: -5]).sign == .mixed)
        #expect(CurrencyAmounts([.usd: 10, .rub: -5]).isEven == false)
    }

    @Test func showsThePreferredCurrencyFirstAndHidesZeros() {
        let amounts = CurrencyAmounts([.usd: 100, .rub: 2_000])
        #expect(amounts.displayed(preferred: .usd).map(\.currency) == [.usd, .rub])
        #expect(amounts.displayed(preferred: .rub).map(\.currency) == [.rub, .usd])
        #expect(CurrencyAmounts([.usd: 0, .rub: 2_000]).displayed(preferred: .usd).map(\.currency) == [.rub])
    }

    @Test func zeroTotalsShowOneZero() {
        #expect(CurrencyAmounts().displayed(preferred: .rub) == [CurrencyAmount(currency: .rub, amount: 0)])
        #expect(CurrencyAmounts([.usd: 0]).displayed(preferred: .rub) == [CurrencyAmount(currency: .usd, amount: 0)])
        #expect(
            CurrencyAmounts([.usd: 0, .rub: 0]).displayed(preferred: .usd) == [CurrencyAmount(currency: .usd, amount: 0)])
    }

    @Test func aSingleCurrencyReadsExactlyAsBefore() {
        for locale in [en, Locale(identifier: "ru_RU")] {
            #expect(
                formattedAmounts(CurrencyAmounts([.rub: 12_500]), preferred: .usd, locale: locale)
                    == formattedCurrency(12_500, code: "RUB", locale: locale))
            #expect(
                formattedSignedAmounts(CurrencyAmounts([.usd: -40]), preferred: .usd, locale: locale)
                    == formattedSignedCurrency(-40, code: "USD", locale: locale))
            #expect(
                formattedAmounts(CurrencyAmounts(), preferred: .usd, locale: locale)
                    == formattedCurrency(0, code: "USD", locale: locale))
        }
    }

    @Test func severalCurrenciesAreListedNotAdded() {
        let net = CurrencyAmounts([.usd: 50, .rub: -2_000])

        #expect(
            formattedSignedAmounts(net, preferred: .usd, locale: en)
                == "+\(formattedCurrency(50, code: "USD", locale: en)) · \u{2212}\(formattedCurrency(2_000, code: "RUB", locale: en))"
        )
        #expect(amountLines(net, preferred: .rub, locale: en).count == 2)
    }

    @Test func magnitudeIsComparedWithinEachCurrency() {
        #expect(CurrencyAmounts.largerMagnitude(CurrencyAmounts([.usd: -90]), CurrencyAmounts([.usd: 60])) == true)
        #expect(CurrencyAmounts.largerMagnitude(CurrencyAmounts([.usd: 60]), CurrencyAmounts([.usd: -60])) == nil)
        // Rubles come first in `allCases`, so any ruble difference decides before dollars do.
        #expect(
            CurrencyAmounts.largerMagnitude(CurrencyAmounts([.rub: 10, .usd: 1]), CurrencyAmounts([.usd: 1_000]))
                == true)
    }

    @Test func comparisonBarsNeedOneCurrency() {
        let a = Person(id: "a", name: "A", colorHex: 0)
        let b = Person(id: "b", name: "B", colorHex: 0)
        func comparison(_ aToB: CurrencyAmounts, _ bToA: CurrencyAmounts) -> PersonComparison {
            PersonComparison(a: a, b: b, aToBValue: aToB, aToBCount: 1, bToAValue: bToA, bToACount: 1)
        }

        #expect(comparison(CurrencyAmounts(), CurrencyAmounts()).comparableValues.map { [$0.aToB, $0.bToA] } == [0, 0])
        #expect(
            comparison(CurrencyAmounts([.rub: 300]), CurrencyAmounts([.rub: 100])).comparableValues.map {
                [$0.aToB, $0.bToA]
            } == [300, 100])
        #expect(comparison(CurrencyAmounts([.usd: 3]), CurrencyAmounts([.rub: 100])).comparableValues == nil)
        // A zero in another currency has nothing to convert, so the bar still shows.
        #expect(
            comparison(CurrencyAmounts([.usd: 100]), CurrencyAmounts([.rub: 0])).comparableValues.map {
                [$0.aToB, $0.bToA]
            } == [100, 0])
    }

    @Test func balancesWithSeveralCurrenciesSortWithoutConverting() {
        func gift(_ id: String, from: String, to: String, _ value: Double, _ currency: SupportedCurrency) -> Gift {
            Gift(
                id: id, emoji: "🎁", name: id, giverID: from, recipientID: to, paidByYou: false, occasion: "",
                date: AppDate.today, value: value, currency: currency, createdAt: AppDate.today)
        }
        let people = [
            Person(id: "me", name: "Me", colorHex: 0), Person(id: "ann", name: "Ann", colorHex: 0),
            Person(id: "bo", name: "Bo", colorHex: 0)
        ]
        let gifts = [
            gift("1", from: "ann", to: "me", 100, .usd),
            gift("2", from: "bo", to: "me", 1_000, .rub)
        ]

        let balances = BuildInsightsUseCase().balances(gifts: gifts, people: people, relativeTo: "me", year: nil)

        #expect(balances.map(\.person.id) == ["bo", "ann"])
        #expect(balances.map(\.net) == [CurrencyAmounts([.rub: 1_000]), CurrencyAmounts([.usd: 100])])
    }
}
