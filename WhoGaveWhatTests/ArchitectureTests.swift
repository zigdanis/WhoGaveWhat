import Foundation
import Testing
@testable import WhoGaveWhat

@MainActor
struct SeededDataTests {
    @Test func loadsTheSampleDatasetThroughGateways() {
        let composition = makeTestComposition()
        #expect(composition.data.gifts.count == 12)
        #expect(composition.data.members.count == 4)
        #expect(composition.data.people.count == 6)
    }

    @Test func insightsSplitAndSumGifts() {
        let composition = makeTestComposition()
        let insights = composition.buildInsights.execute(
            gifts: composition.data.gifts,
            people: composition.data.people
        )
        #expect(insights.received.count == 7)
        #expect(insights.given.count == 5)
        #expect(insights.receivedValue == 19_300)
        #expect(insights.givenValue == 11_800)
        #expect([Gift]().totalValue == 0)
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

    @Test func directionDerivesFromHouseholdSide() {
        let composition = makeTestComposition()
        let ids = composition.data.householdIDs
        let useCase = composition.saveGiftUseCase
        #expect(useCase.flow(for: makeGiftInput(fromID: "maria", toID: "you"), householdIDs: ids) == .received)
        #expect(useCase.flow(for: makeGiftInput(fromID: "you", toID: "maria"), householdIDs: ids) == .given)
        #expect(useCase.flow(for: makeGiftInput(fromID: "marina", toID: "igor"), householdIDs: ids) == .given)
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
struct SaveGiftTests {
    @Test func savingUsesSuggestedValueAndReloadsData() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(
            makeGiftInput(name: "Bottle of wine", fromID: "you", toID: "igor"),
            householdIDs: ["you", "marina"]
        )
        let saved = gateway.gifts.first { $0.name == "Bottle of wine" }
        #expect(saved?.value == 1_900)
        #expect(saved?.emoji == "🍷")
        #expect(saved?.flow == .given)
        #expect(saved?.personId == "igor")
        #expect(saved?.memberId == "you")
        #expect(saved?.paidByYou == true)
    }

    @Test func touchedValueOverridesSuggestion() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(makeGiftInput(
            name: "Bottle of wine", fromID: "you", toID: "igor", value: 2_500,
            valueTouched: true), householdIDs: ["you"])
        #expect(gateway.gifts.contains { $0.name == "Bottle of wine" && $0.value == 2_500 })
    }

    @Test func receivedGiftCanBeMarkedPaidByYou() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(makeGiftInput(
            name: "Soft teddy", fromID: "maria", toID: "you", paidByYou: true
        ), householdIDs: ["you"])
        let saved = gateway.gifts.first { $0.name == "Soft teddy" }
        #expect(saved?.flow == .received)
        #expect(saved?.paidByYou == true)
    }

    @Test func familyMemberGiftKeepsPaidByYouFalse() {
        let (useCase, gateway) = makeSaveGiftUseCase()
        _ = try? useCase.execute(makeGiftInput(
            name: "Marina's wine", fromID: "marina", toID: "igor"
        ), householdIDs: ["you", "marina"])
        let saved = gateway.gifts.first { $0.name == "Marina's wine" }
        #expect(saved?.flow == .given)
        #expect(saved?.memberId == "marina")
        #expect(saved?.personId == "igor")
        #expect(saved?.paidByYou == false)
    }
}

struct OrderingTests {
    private func gift(_ id: String, date: Date) -> Gift {
        Gift(id: id, emoji: "🎁", name: id, flow: .received, personId: "p",
             memberId: "you", paidByYou: false, celebration: "", date: date, value: 0)
    }

    @Test func creationSeqParsesTheIdSuffix() {
        #expect(gift("g12", date: AppDate.today).creationSeq == 12)
        #expect(gift("g1750000000000", date: AppDate.today).creationSeq == 1_750_000_000_000)
    }

    @Test func sameDayOrdersByCreationDescending() {
        let earlier = gift("g1000", date: AppDate.today)
        let later = gift("g2000", date: AppDate.today)
        #expect(Gift.newestFirst(later, earlier))
        #expect(!Gift.newestFirst(earlier, later))
    }

    @Test func newerDayBeatsCreationSeq() {
        let oldDay = gift("g9999999999999", date: AppDate.yesterday)
        let newDay = gift("g1", date: AppDate.today)
        #expect(Gift.newestFirst(newDay, oldDay))
    }
}

@MainActor
struct SubtitleTests {
    @Test func subtitleIsAlwaysGiverArrowReceiver() {
        let composition = makeTestComposition()
        let data = composition.data
        let received = data.gifts.first { $0.id == "g1" }!
        #expect(data.giftSubtitle(received) ==
                "\(data.personName(received.personId))  →  \(data.memberName(received.memberId))")
        let given = data.gifts.first { $0.id == "g8" }!
        #expect(data.giftSubtitle(given) ==
                "\(data.memberName(given.memberId))  →  \(data.personName(given.personId))")
        #expect(!data.giftSubtitle(given).contains("·"))
    }
}
