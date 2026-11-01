import Foundation
import Testing

@testable import WhoGaveWhat

private let day: TimeInterval = 86_400

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// Noon UTC on 1 November 2026 plus `days`.
private func date(_ days: Double = 0) -> Date {
    Date(timeIntervalSince1970: 1_793_534_400).addingTimeInterval(days * day)
}

/// A state on its third day of use with no request yet.
private func thirdDayState() -> ReviewPromptState {
    ReviewPromptState(activeDays: 3, lastActiveDay: "2026-11-01", firstActiveDate: date(-2))
}

struct ReviewPromptPolicyTests {
    let policy = ReviewPromptPolicy()

    @Test func countsEachCalendarDayOnce() {
        var state = ReviewPromptState()
        state = policy.recordingActiveDay(state, now: date(), calendar: utcCalendar)
        state = policy.recordingActiveDay(state, now: date(0.4), calendar: utcCalendar)
        #expect(state.activeDays == 1)
        #expect(state.firstActiveDate == date())
        #expect(state.lastActiveDay == "2026-11-01")

        state = policy.recordingActiveDay(state, now: date(1), calendar: utcCalendar)
        state = policy.recordingActiveDay(state, now: date(5), calendar: utcCalendar)
        #expect(state.activeDays == 3)
        #expect(state.firstActiveDate == date())
        #expect(policy.daysSinceFirstActive(state, now: date(5), calendar: utcCalendar) == 5)
    }

    @Test func asksFromTheThirdDayWithEnoughGiftsAndPeople() {
        var early = thirdDayState()
        early.activeDays = 2
        #expect(!policy.shouldRequest(early, now: date(), version: "1.1", giftsCount: 10, peopleCount: 4))
        #expect(policy.shouldRequest(thirdDayState(), now: date(), version: "1.1", giftsCount: 5, peopleCount: 2))
        #expect(!policy.shouldRequest(thirdDayState(), now: date(), version: "1.1", giftsCount: 4, peopleCount: 2))
        #expect(!policy.shouldRequest(thirdDayState(), now: date(), version: "1.1", giftsCount: 5, peopleCount: 1))
    }

    @Test func recordingARequestResetsTheEngagementSinceIt() {
        var state = thirdDayState()
        state.giftsCreatedSinceRequest = 4
        state.activeDaysSinceRequest = 3
        state.requestDates = [date(-400), date(-200)]
        state.requestCount = 2
        state = policy.recordingRequest(state, now: date(), version: "1.1")
        #expect(state.requestDates == [date(-200), date()])
        #expect(state.requestCount == 3)
        #expect(state.lastRequestVersion == "1.1")
        #expect(state.giftsCreatedSinceRequest == 0)
        #expect(state.activeDaysSinceRequest == 0)
    }

    @Test func asksAgainOnlyForANewVersionAfterTheCooldownAndNewUse() {
        let asked = policy.recordingRequest(thirdDayState(), now: date(), version: "1.1")
        var later = asked
        later.giftsCreatedSinceRequest = 3
        later.activeDaysSinceRequest = 2

        #expect(!policy.shouldRequest(later, now: date(200), version: "1.1", giftsCount: 20, peopleCount: 5))
        #expect(!policy.shouldRequest(later, now: date(119), version: "1.2", giftsCount: 20, peopleCount: 5))
        #expect(policy.shouldRequest(later, now: date(120), version: "1.2", giftsCount: 20, peopleCount: 5))

        var fewGifts = later
        fewGifts.giftsCreatedSinceRequest = 2
        #expect(!policy.shouldRequest(fewGifts, now: date(200), version: "1.2", giftsCount: 20, peopleCount: 5))
        var fewDays = later
        fewDays.activeDaysSinceRequest = 1
        #expect(!policy.shouldRequest(fewDays, now: date(200), version: "1.2", giftsCount: 20, peopleCount: 5))
    }

    @Test func asksAtMostThreeTimesInAYear() {
        var state = thirdDayState()
        state.requestDates = [date(-360), date(-240), date(-121)]
        state.lastRequestVersion = "1.3"
        state.giftsCreatedSinceRequest = 5
        state.activeDaysSinceRequest = 5
        #expect(!policy.shouldRequest(state, now: date(), version: "1.4", giftsCount: 20, peopleCount: 5))

        state.requestDates[0] = date(-366)
        #expect(policy.shouldRequest(state, now: date(), version: "1.4", giftsCount: 20, peopleCount: 5))
    }
}

@MainActor
struct ReviewPromptUseCaseTests {
    private func makeUseCase(
        state: ReviewPromptState = thirdDayState(), isEnabled: Bool = true
    ) -> (ReviewPromptUseCase, TestPreferencesGateway) {
        let preferences = TestPreferencesGateway()
        preferences.reviewPromptState = state
        let useCase = ReviewPromptUseCase(
            preferences: preferences, version: "1.1", isEnabled: isEnabled, now: { date() }, calendar: utcCalendar)
        return (useCase, preferences)
    }

    @Test func asksOncePerSessionAndRecordsTheRequest() {
        let (useCase, preferences) = makeUseCase()
        #expect(useCase.newGiftSaved(giftsCount: 5, peopleCount: 2))
        #expect(preferences.reviewPromptState.giftsCreatedSinceRequest == 1)

        let event = useCase.recordRequest(giftsCount: 5, peopleCount: 2)
        #expect(
            event == .reviewPromptRequested(activeDays: 3, daysSinceFirstLaunch: 2, giftsCount: 5, peopleCount: 2, requestNumber: 1))
        #expect(preferences.reviewPromptState.lastRequestVersion == "1.1")
        #expect(!useCase.newGiftSaved(giftsCount: 6, peopleCount: 2))
    }

    @Test func aSetbackWaitsForTheNextSession() {
        let (useCase, _) = makeUseCase()
        useCase.noteSetback()
        #expect(!useCase.newGiftSaved(giftsCount: 5, peopleCount: 2))
        useCase.appEnteredBackground()
        #expect(useCase.newGiftSaved(giftsCount: 6, peopleCount: 2))
    }

    @Test func aDisabledLaunchStillCountsGiftsButNeverAsks() {
        let (useCase, preferences) = makeUseCase(isEnabled: false)
        #expect(!useCase.newGiftSaved(giftsCount: 5, peopleCount: 2))
        #expect(preferences.reviewPromptState.giftsCreatedSinceRequest == 1)
    }

    @Test func comingToTheForegroundCountsTheDay() {
        var state = thirdDayState()
        state.activeDays = 2
        state.lastActiveDay = "2026-10-31"
        let (useCase, preferences) = makeUseCase(state: state)
        useCase.appBecameActive()
        useCase.appBecameActive()
        #expect(preferences.reviewPromptState.activeDays == 3)
        #expect(useCase.newGiftSaved(giftsCount: 5, peopleCount: 2))
    }
}

@MainActor
struct ReviewPromptCompositionTests {
    private func makeComposition(
        state: ReviewPromptState = thirdDayState(),
        launchEnvironment: [String: String] = [:],
        analytics: AnalyticsGateway = NoopAnalyticsGateway()
    ) throws -> (AppComposition, TestPreferencesGateway) {
        let preferences = TestPreferencesGateway()
        preferences.selfPersonID = SwiftDataStore.seedSelfPersonID
        preferences.reviewPromptState = state
        let composition = AppComposition(
            store: try SwiftDataStore(inMemory: true, seed: true),
            preferences: preferences,
            intelligence: TestIntelligenceGateway(),
            launchEnvironment: launchEnvironment,
            analytics: analytics)
        return (composition, preferences)
    }

    private var newGift: SaveGiftInput {
        makeGiftInput(name: "Book set", fromID: "maria", toID: "anton")
    }

    @Test func aNewGiftOnTheThirdDayMakesTheRequestPending() throws {
        let analytics = RecordingAnalyticsGateway()
        let (composition, preferences) = try makeComposition(analytics: analytics)
        #expect(composition.saveGift(newGift))
        #expect(composition.isReviewRequestPending)

        composition.reviewRequestPresented()
        #expect(!composition.isReviewRequestPending)
        #expect(analytics.eventNames.last == "review_prompt_requested")
        #expect(preferences.reviewPromptState.requestCount == 1)

        #expect(composition.saveGift(newGift))
        #expect(!composition.isReviewRequestPending)
    }

    @Test func editsAndEarlyDaysDoNotAsk() throws {
        var early = thirdDayState()
        early.activeDays = 2
        let (earlyComposition, _) = try makeComposition(state: early)
        #expect(earlyComposition.saveGift(newGift))
        #expect(!earlyComposition.isReviewRequestPending)

        let (composition, preferences) = try makeComposition()
        let existing = try #require(composition.data.gifts.first)
        var edit = newGift
        edit.editingGiftID = existing.id
        edit.createdAt = existing.createdAt
        #expect(composition.saveGift(edit))
        #expect(!composition.isReviewRequestPending)
        #expect(preferences.reviewPromptState.giftsCreatedSinceRequest == 0)
    }

    @Test func aDeletionWaitsForTheNextSessionAndASkippedMomentCanReturn() throws {
        let (composition, _) = try makeComposition()
        let existing = try #require(composition.data.gifts.first)
        composition.deleteGift(id: existing.id, source: .home)
        #expect(composition.saveGift(newGift))
        #expect(!composition.isReviewRequestPending)

        composition.sceneEnteredBackground()
        #expect(!composition.isSceneActive)
        composition.sceneBecameActive()
        #expect(composition.isSceneActive)
        #expect(composition.saveGift(newGift))
        #expect(composition.isReviewRequestPending)

        composition.sceneBecameInactive()
        #expect(!composition.isSceneActive)
        composition.reviewRequestSkipped()
        #expect(!composition.isReviewRequestPending)
        #expect(composition.saveGift(newGift))
        #expect(composition.isReviewRequestPending)
    }

    @Test func verificationLaunchesAskOnlyWhenReady() throws {
        let (silent, _) = try makeComposition(launchEnvironment: ["KS_TAB": "home"])
        #expect(silent.saveGift(newGift))
        #expect(!silent.isReviewRequestPending)

        let (ready, preferences) = try makeComposition(
            state: ReviewPromptState(), launchEnvironment: ["KS_REVIEW_PROMPT": "ready"])
        #expect(preferences.reviewPromptState.activeDays == 3)
        #expect(ready.saveGift(newGift))
        #expect(ready.isReviewRequestPending)
    }

    @Test func userDefaultsGatewayKeepsTheState() throws {
        let suite = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let gateway = UserDefaultsPreferencesGateway(defaults: defaults)
        #expect(gateway.reviewPromptState == ReviewPromptState())

        let state = ReviewPromptPolicy().recordingRequest(thirdDayState(), now: date(), version: "1.1")
        gateway.setReviewPromptState(state)
        #expect(UserDefaultsPreferencesGateway(defaults: defaults).reviewPromptState == state)
    }
}
