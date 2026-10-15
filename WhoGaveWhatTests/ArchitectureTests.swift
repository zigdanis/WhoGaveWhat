import Foundation
import Testing

@testable import WhoGaveWhat

@MainActor
struct SeededDataTests {
    @Test func loadsTheSampleDatasetThroughGateways() throws {
        let composition = try makeTestComposition()
        #expect(composition.data.gifts.count == 12)
        #expect(composition.data.people.count == 10)
        #expect(composition.data.selfPersonID == "anton")
        #expect(composition.data.isSelf("anton"))
        #expect(!composition.data.isSelf("marina"))
    }

    @Test func yearSummarySplitsAndSumsTheSeededYear() throws {
        let composition = try makeTestComposition()
        let useCase = composition.buildInsights
        let year = try #require(useCase.availableYears(gifts: composition.data.gifts).first)
        let summary = useCase.summary(gifts: composition.data.gifts, relativeTo: composition.data.selfPersonID, year: year)
        #expect(summary.year == year)
        #expect(summary.receivedCount == 3)
        #expect(summary.givenCount == 3)
        #expect(summary.receivedValue == 13_200)
        #expect(summary.givenValue == 5_800)
        #expect(summary.net == 7_400)
        #expect(summary.circulatedValue == 31_100)
        #expect(summary.giftCount == 12)
        #expect([Gift]().totalValue == 0)
    }

    @Test func yearSummaryWithoutViewpointHasNoBalance() throws {
        let composition = try makeTestComposition(selfPersonID: nil)
        let useCase = composition.buildInsights
        let year = try #require(useCase.availableYears(gifts: composition.data.gifts).first)
        let summary = useCase.summary(gifts: composition.data.gifts, relativeTo: composition.data.selfPersonID, year: year)
        #expect(summary.receivedCount == 0)
        #expect(summary.givenCount == 0)
        #expect(summary.net == 0)
        #expect(summary.circulatedValue == 31_100)
    }

    @Test func balancesRankTheSeededCounterpartsByAbsoluteNet() throws {
        let composition = try makeTestComposition()
        let useCase = composition.buildInsights
        let balances = useCase.balances(
            gifts: composition.data.gifts, people: composition.data.people, relativeTo: "anton", year: nil)
        #expect(balances.first?.person.id == "pavel")
        #expect(balances.first?.net == 9_500)
        #expect(balances.map(\.person.id).contains("anton") == false)
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

    @Test func draftDirectionIsRelativeToTheViewpoint() throws {
        let composition = try makeTestComposition()
        let state = AddGiftState(
            route: .create,
            data: composition.data,
            suggestGift: composition.suggestGift
        )
        #expect(state.direction(relativeTo: "anton") == nil)

        state.selectFrom("maria")
        state.selectTo("anton")
        #expect(state.direction(relativeTo: "anton") == .received)
        #expect(state.direction(relativeTo: "maria") == .given)
        #expect(state.direction(relativeTo: "igor") == nil)
        #expect(state.direction(relativeTo: nil) == nil)
    }
}

struct GiftViewpointTests {
    @Test func directionIsRelativeToTheViewpointPerson() {
        let gift = makeGift(giverID: "maria", recipientID: "igor")
        #expect(gift.direction(relativeTo: "maria") == .given)
        #expect(gift.direction(relativeTo: "igor") == .received)
        #expect(gift.direction(relativeTo: "olga") == nil)
        #expect(gift.direction(relativeTo: nil) == nil)
    }

    @Test func timelineFilterFollowsTheViewpoint() {
        let gifts = [
            makeGift(id: "in", giverID: "maria", recipientID: "igor"),
            makeGift(id: "out", giverID: "igor", recipientID: "maria"),
            makeGift(id: "other", giverID: "maria", recipientID: "olga")
        ]
        let useCase = BuildGiftTimelineUseCase()
        func ids(_ filter: String, _ viewpoint: String?) -> Set<String> {
            Set(useCase.execute(gifts: gifts, filter: filter, relativeTo: viewpoint).flatMap(\.gifts).map(\.id))
        }
        #expect(ids("all", nil) == ["in", "out", "other"])
        #expect(ids("received", "igor") == ["in"])
        #expect(ids("given", "igor") == ["out"])
        #expect(ids("received", nil).isEmpty)
    }

    @Test func timelineSectionsCarryTheirMonthTotal() {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date()) - 3
        func gift(_ id: String, month: Int, value: Double) -> Gift {
            var result = makeGift(id: id, giverID: "maria", recipientID: "igor")
            result.date = calendar.date(from: DateComponents(year: year, month: month, day: 10, hour: 12))!
            result.value = value
            return result
        }
        let sections = BuildGiftTimelineUseCase().execute(
            gifts: [gift("a", month: 3, value: 10), gift("b", month: 3, value: 5), gift("c", month: 4, value: 7)],
            filter: "all",
            relativeTo: nil,
            displayYear: year,
            locale: Locale(identifier: "en_US")
        )
        #expect(sections.map(\.label) == ["April", "March"])
        #expect(sections.map(\.total) == [7, 15])
    }

    private func makeGift(id: String = "g", giverID: String, recipientID: String) -> Gift {
        Gift(
            id: id, emoji: "🎁", name: id, giverID: giverID, recipientID: recipientID,
            paidByYou: false, occasion: "", date: AppDate.today, value: 0,
            createdAt: AppDate.today)
    }
}

@MainActor
struct SelfPersonTests {
    @Test func settingTheViewpointPersistsAndKeepsExactlyOne() throws {
        let preferences = TestPreferencesGateway()
        let composition = AppComposition(
            store: try SwiftDataStore(inMemory: true, seed: true),
            preferences: preferences,
            intelligence: TestIntelligenceGateway()
        )
        #expect(composition.data.selfPersonID == nil)

        composition.markSelf(true, personID: "marina")
        composition.markSelf(true, personID: "igor")
        #expect(composition.data.selfPersonID == "igor")
        #expect(preferences.selfPersonID == "igor")
        #expect(!composition.data.isSelf("marina"))

        composition.markSelf(false, personID: "marina")
        #expect(composition.data.selfPersonID == "igor")
        composition.markSelf(false, personID: "igor")
        #expect(composition.data.selfPersonID == nil)
        #expect(preferences.selfPersonID == nil)
    }

    @Test func resetSelfLaunchFlagClearsOnlyWhenSet() throws {
        let preferences = TestPreferencesGateway()
        preferences.selfPersonID = "anton"
        let kept = AppComposition(
            store: try SwiftDataStore(inMemory: true, seed: true),
            preferences: preferences,
            intelligence: TestIntelligenceGateway(),
            launchEnvironment: [:]
        )
        #expect(kept.data.selfPersonID == "anton")
        #expect(preferences.selfPersonID == "anton")

        let reset = AppComposition(
            store: try SwiftDataStore(inMemory: true, seed: true),
            preferences: preferences,
            intelligence: TestIntelligenceGateway(),
            launchEnvironment: ["KS_RESET_SELF": "1"]
        )
        #expect(reset.data.selfPersonID == nil)
        #expect(preferences.selfPersonID == nil)
    }

    @Test func deletingTheViewpointPersonClearsIt() throws {
        let composition = try makeTestComposition()
        composition.deletePerson(id: "marina")
        #expect(composition.data.selfPersonID == "anton")

        composition.deletePerson(id: "anton")
        #expect(composition.data.selfPersonID == nil)
        #expect(composition.data.people.contains { $0.id == "anton" } == false)
    }

    @Test func userDefaultsGatewayPersistsAndClearsTheViewpoint() {
        let suiteName = "SelfPersonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let gateway = UserDefaultsPreferencesGateway(defaults: defaults)
        #expect(gateway.selfPersonID == nil)

        gateway.setSelfPersonID("anton")
        #expect(UserDefaultsPreferencesGateway(defaults: defaults).selfPersonID == "anton")

        gateway.setSelfPersonID(nil)
        #expect(UserDefaultsPreferencesGateway(defaults: defaults).selfPersonID == nil)
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
        Person(id: "alex", name: "Alex", colorHex: 0x123456),
        Person(id: "alice", name: "Alice", colorHex: 0x654321),
        Person(id: "bob", name: "Bob", colorHex: 0xABCDEF)
    ]

    @Test func initialMissingOrInvalidSelectionDefaultsToFirstPerson() {
        let missingState = PersonPickerState(people: people, selectedID: nil)
        let invalidState = PersonPickerState(people: people, selectedID: "missing")

        #expect(missingState.selectedID == "alex")
        #expect(invalidState.selectedID == "alex")
    }

    @Test func initialSelectionPreservesAValidPerson() {
        let state = PersonPickerState(people: people, selectedID: "bob")

        #expect(state.selectedID == "bob")
    }

    @Test func filtersAndProvisionallySelectsTheFirstMatch() {
        let state = PersonPickerState(people: people, selectedID: "bob")

        let selection = state.updateQuery("Al")

        #expect(state.visiblePeople.map(\.id) == ["alex", "alice"])
        #expect(selection == "alex")
        #expect(state.selectedID == "alex")
    }

    @Test func clearsSelectionWhenAQueryHasNoMatches() {
        let state = PersonPickerState(people: people, selectedID: "bob")

        let selection = state.updateQuery("New person")

        #expect(state.visiblePeople.isEmpty)
        #expect(selection == nil)
        #expect(state.selectedID == nil)
    }

    @Test func clearingQueryRestoresAllPeopleAndSelectsTheFirst() {
        let state = PersonPickerState(people: people, selectedID: nil)
        _ = state.updateQuery("Ali")

        let selection = state.updateQuery("")

        #expect(state.visiblePeople.map(\.id) == people.map(\.id))
        #expect(selection == "alex")
        #expect(state.selectedID == "alex")
    }

    @Test func newlyCreatedPersonFlowsThroughFromSelection() throws {
        let composition = try makeTestComposition()
        let giftState = AddGiftState(
            route: .create,
            data: composition.data,
            suggestGift: composition.suggestGift
        )
        let pickerState = PersonPickerState(
            people: composition.data.people,
            selectedID: giftState.draft.fromID
        )

        let id = try #require(
            pickerState.createAndSelectPerson(
                named: "Dana",
                create: { composition.createPerson(name: $0) },
                select: giftState.selectFrom
            ))

        #expect(giftState.draft.fromID == id)
        #expect(giftState.draft.toID == nil)
        #expect(composition.data.entityName(id) == "Dana")
    }

    @Test func repeatedFinalQueryDoesNotClearNewlyCreatedSelection() throws {
        let composition = try makeTestComposition()
        let giftState = AddGiftState(
            route: .create,
            data: composition.data,
            suggestGift: composition.suggestGift
        )
        let pickerState = PersonPickerState(
            people: composition.data.people,
            selectedID: giftState.draft.fromID
        )
        _ = pickerState.updateQuery("Dana")

        let id = try #require(
            pickerState.createAndSelectPerson(
                named: "Dana",
                create: { composition.createPerson(name: $0) },
                select: giftState.selectFrom
            ))

        #expect(pickerState.updateQuery("Dana") == id)
        #expect(giftState.draft.fromID == id)
    }

    @Test func duplicatePersonFlowsThroughToSelection() throws {
        let composition = try makeTestComposition()
        let existingPerson = try #require(composition.data.people.first)
        let initialPeopleCount = composition.data.people.count
        let giftState = AddGiftState(
            route: .create,
            data: composition.data,
            suggestGift: composition.suggestGift
        )
        let pickerState = PersonPickerState(
            people: composition.data.people,
            selectedID: giftState.draft.toID
        )

        let id = try #require(
            pickerState.createAndSelectPerson(
                named: existingPerson.name.uppercased(),
                create: { composition.createPerson(name: $0) },
                select: giftState.selectTo
            ))

        #expect(id == existingPerson.id)
        #expect(giftState.draft.fromID == nil)
        #expect(giftState.draft.toID == existingPerson.id)
        #expect(composition.data.people.count == initialPeopleCount)
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
struct CurrencyPreferenceTests {
    @Test func compositionPublishesAndPersistsCurrencyChanges() throws {
        let preferences = TestPreferencesGateway()
        let composition = AppComposition(
            store: try SwiftDataStore(inMemory: true),
            preferences: preferences,
            intelligence: TestIntelligenceGateway()
        )

        composition.setCurrencyCode("EUR")

        #expect(composition.currencyCode == "EUR")
        #expect(preferences.currencyCode == "EUR")
    }

    @Test func userDefaultsGatewayPersistsSelectedCurrency() {
        let suiteName = "CurrencyPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let gateway = UserDefaultsPreferencesGateway(defaults: defaults)

        gateway.setCurrencyCode("JPY")

        #expect(UserDefaultsPreferencesGateway(defaults: defaults).currencyCode == "JPY")
    }
}

@MainActor
struct SaveGiftTests {
    @Test func savingUsesSuggestedEmojiButLeavesUntouchedValueAtZero() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(
            makeGiftInput(name: "Bottle of wine", fromID: "you", toID: "igor")
        )
        let saved = gateway.gifts.first { $0.name == "Bottle of wine" }
        #expect(saved?.value == 0)
        #expect(saved?.emoji == "🍷")
        #expect(saved?.direction(relativeTo: "you") == .given)
        #expect(saved?.giverID == "you")
        #expect(saved?.recipientID == "igor")
        #expect(saved?.paidByYou == false)
    }

    @Test func touchedValueOverridesSuggestion() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(
            makeGiftInput(
                name: "Bottle of wine", fromID: "you", toID: "igor", value: 2_500,
                valueTouched: true))
        #expect(gateway.gifts.contains { $0.name == "Bottle of wine" && $0.value == 2_500 })
    }

    @Test func receivedGiftCanBeMarkedPaidByYou() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(
            makeGiftInput(
                name: "Soft teddy", fromID: "maria", toID: "you", paidByYou: true
            ))
        let saved = gateway.gifts.first { $0.name == "Soft teddy" }
        #expect(saved?.direction(relativeTo: "you") == .received)
        #expect(saved?.paidByYou == true)
    }

    @Test func thirdPartyGiftKeepsPaidByYouFalse() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(
            makeGiftInput(
                name: "Marina's wine", fromID: "marina", toID: "igor"
            ))
        let saved = gateway.gifts.first { $0.name == "Marina's wine" }
        #expect(saved?.direction(relativeTo: "you") == nil)
        #expect(saved?.direction(relativeTo: "marina") == .given)
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

        try useCase.execute(input)

        #expect(gateway.gifts.first?.id == "existing-id")
        #expect(gateway.gifts.first?.createdAt == createdAt)
    }
}

struct OrderingTests {
    private func gift(_ id: String, date: Date, createdAt: Date) -> Gift {
        Gift(
            id: id, emoji: "🎁", name: id, giverID: "p",
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
    @Test func subtitleIsAlwaysGiverArrowReceiver() throws {
        let composition = try makeTestComposition()
        let data = composition.data
        let received = data.gifts.first { $0.id == "g1" }!
        #expect(data.giftSubtitle(received) == "\(data.entityName(received.giverID))  →  \(data.entityName(received.recipientID))")
        let given = data.gifts.first { $0.id == "g8" }!
        #expect(data.giftSubtitle(given) == "\(data.entityName(given.giverID))  →  \(data.entityName(given.recipientID))")
        #expect(!data.giftSubtitle(given).contains("·"))
    }
}
