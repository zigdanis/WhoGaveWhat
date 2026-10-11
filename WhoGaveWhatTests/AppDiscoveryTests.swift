import CoreSpotlight
import Foundation
import Testing

@testable import WhoGaveWhat

@MainActor
struct AppDiscoveryTests {
    @Test(arguments: ["Who Gave", "кто че"])
    func launcherIsSearchableInBothLanguagesRegardlessOfTitle(title: String) {
        let item = AppDiscoveryIndexer.makeItem(title: title)
        let attributes = item.attributeSet

        #expect(attributes.title == title)
        #expect(attributes.displayName == title)
        #expect(attributes.contentDescription == "Who Gave; Who Gave What; WhoGaveWhat; кто че; кто чё")
        for alias in ["Who Gave", "Who Gave What", "WhoGaveWhat", "кто че", "кто чё"] {
            #expect(attributes.alternateNames?.contains(alias) == true)
            #expect(attributes.keywords?.contains(alias) == true)
        }
        #expect(item.uniqueIdentifier == "pro.ziganshin.WhoGaveWhat.launch")
        #expect(item.domainIdentifier == "pro.ziganshin.WhoGaveWhat.app-discovery")
        #expect(item.expirationDate == .distantFuture)
    }

    @Test func launcherDoesNotIndexPrivateAppData() async throws {
        let recorder = AppDiscoveryIndexRecorder()
        let indexer = AppDiscoveryIndexer(indexItems: recorder.indexItems)

        await indexer.refresh()

        let items = try #require(recorder.attempts.first)
        #expect(items.count == 1)
        let attributes = try #require(items.first).attributeSet
        // The searchable description contains public app names only, never gift or person data.
        #expect(attributes.contentDescription == "Who Gave; Who Gave What; WhoGaveWhat; кто че; кто чё")
        #expect(attributes.textContent == nil)
        #expect(attributes.contentURL == nil)
        #expect(attributes.relatedUniqueIdentifier == nil)
        #expect(
            attributes.keywords == [
                "Who Gave", "Who Gave What", "WhoGaveWhat", "кто че", "кто чё",
                "who", "gave", "what", "кто", "че", "чё"
            ])
    }

    @Test func aLaterActivationRetriesAfterFailureAndRefreshesAfterSuccess() async {
        let recorder = AppDiscoveryIndexRecorder()
        recorder.failuresRemaining = 1
        let indexer = AppDiscoveryIndexer(indexItems: recorder.indexItems)

        await indexer.refresh()
        await indexer.refresh()
        await indexer.refresh()

        #expect(recorder.attempts.count == 3)
        #expect(recorder.failuresRemaining == 0)
        #expect(recorder.attempts.allSatisfy { $0.count == 1 })
        #expect(recorder.attempts.allSatisfy { $0.first?.uniqueIdentifier == AppDiscoveryIndexer.itemIdentifier })
    }

    @Test func overlappingRequestsCoalesceAndNextActivationStillRefreshes() async {
        let recorder = AppDiscoveryIndexRecorder()
        recorder.blocksNextRequest = true
        let indexer = AppDiscoveryIndexer(indexItems: recorder.indexItems)
        let firstRequest = Task { await indexer.refresh() }
        await recorder.waitUntilBlocked()

        await indexer.refresh()
        #expect(recorder.attempts.count == 1)

        recorder.releaseRequest()
        await firstRequest.value
        await indexer.refresh()
        #expect(recorder.attempts.count == 2)
    }

    @Test func launchActivityPreservesColdOnboardingAndSignIn() throws {
        let composition = try makeTestComposition()
        #expect(composition.router.screen == .onboarding)

        #expect(composition.continueAppDiscovery(launcherActivity()))
        #expect(composition.router.screen == .onboarding)

        composition.router.showSignIn()
        #expect(composition.continueAppDiscovery(launcherActivity()))
        #expect(composition.router.screen == .signIn)
    }

    @Test(arguments: [AppTab.home, .people, .insights])
    func launchActivityPreservesWarmNavigationAndOpenGift(tab: AppTab) throws {
        let composition = try makeTestComposition()
        let router = composition.router
        router.showMainApp()
        router.selectTab(tab)
        router.presentEditGift(id: "g1")
        router.presentSettings()

        #expect(composition.continueAppDiscovery(launcherActivity()))
        #expect(router.screen == .main)
        #expect(router.tab == tab)
        #expect(router.giftSheet == .edit(giftID: "g1"))
        #expect(router.showsSettings)

        router.presentNewGift()
        #expect(composition.continueAppDiscovery(launcherActivity()))
        #expect(router.giftSheet == .create)
    }

    @Test func rejectsUnrelatedMissingAndMalformedActivitiesWithoutChangingRoute() throws {
        let composition = try makeTestComposition()
        composition.router.selectTab(.people)
        composition.router.presentNewGift()
        let unrelated = NSUserActivity(activityType: "pro.ziganshin.WhoGaveWhat.unrelated")
        unrelated.userInfo = [CSSearchableItemActivityIdentifier: AppDiscoveryIndexer.itemIdentifier]
        let missing = NSUserActivity(activityType: CSSearchableItemActionType)
        let wrongIdentifier = launcherActivity()
        wrongIdentifier.userInfo = [CSSearchableItemActivityIdentifier: "unknown"]
        let malformed = launcherActivity()
        malformed.userInfo = [CSSearchableItemActivityIdentifier: 42]

        for activity in [unrelated, missing, wrongIdentifier, malformed] {
            #expect(!composition.continueAppDiscovery(activity))
            #expect(composition.router.screen == .onboarding)
            #expect(composition.router.tab == .people)
            #expect(composition.router.giftSheet == .create)
        }
    }

    private func launcherActivity() -> NSUserActivity {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: AppDiscoveryIndexer.itemIdentifier]
        return activity
    }
}

@MainActor
private final class AppDiscoveryIndexRecorder {
    var attempts: [[CSSearchableItem]] = []
    var failuresRemaining = 0
    var blocksNextRequest = false
    private var blockedRequest: CheckedContinuation<Void, Never>?
    private var blockWaiter: CheckedContinuation<Void, Never>?

    func indexItems(_ items: [CSSearchableItem]) async throws {
        attempts.append(items)
        if blocksNextRequest {
            blocksNextRequest = false
            await withCheckedContinuation { continuation in
                blockedRequest = continuation
                blockWaiter?.resume()
                blockWaiter = nil
            }
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw IndexingFailure.unavailable
        }
    }

    func waitUntilBlocked() async {
        guard blockedRequest == nil else { return }
        await withCheckedContinuation { blockWaiter = $0 }
    }

    func releaseRequest() {
        blockedRequest?.resume()
        blockedRequest = nil
    }

    private enum IndexingFailure: Error {
        case unavailable
    }
}
