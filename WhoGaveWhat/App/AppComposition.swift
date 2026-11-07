import Foundation
import Observation

@MainActor
@Observable
final class AppComposition {
    let router: AppRouter
    let appDiscovery: AppDiscoveryIndexer
    let data = AppData()
    let analytics: AnalyticsGateway
    let haptics: HapticsGateway
    private(set) var currencyCode: String
    /// Set when a new gift makes this the moment to ask for an App Store rating; the root view
    /// asks once the gift sheet has closed, then reports back.
    private(set) var isReviewRequestPending = false
    /// Whether the app is in the foreground and taking input, kept live from the scene phase.
    private(set) var isSceneActive = false
    let reviewPrompt: ReviewPromptUseCase
    let preferences: PreferencesGateway
    private let peopleGateway: PeopleGateway

    let loadGiftsUseCase: LoadGiftsUseCase
    let saveGiftUseCase: SaveGiftUseCase
    let deleteGiftUseCase: DeleteGiftUseCase
    let suggestGift: SuggestGiftUseCase
    let buildTimeline = BuildGiftTimelineUseCase()
    let loadPersonGifts = LoadPersonGiftsUseCase()
    let loadPeopleUseCase: LoadPeopleUseCase
    let createPersonUseCase: CreatePersonUseCase
    let renamePersonUseCase: RenamePersonUseCase
    let deletePersonUseCase: DeletePersonUseCase
    let buildInsights = BuildInsightsUseCase()
    let rankPickerOptions = RankPickerOptionsUseCase()

    convenience init(
        store: SwiftDataStore, preferences: UserDefaultsPreferencesGateway,
        analytics: AnalyticsGateway,
        haptics: HapticsGateway
    ) {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        // Verification launches with `KS_CLOUD_ICONS=stub` get fixed answers only: no network, no on-device model.
        let intelligence: GiftIntelligenceGateway
        if environment["KS_CLOUD_ICONS"] == "stub" {
            intelligence = StubCloudGiftIconGateway()
        } else {
            intelligence = PreferredGiftIntelligenceGateway(
                cloud: CloudGiftIconGateway(preferences: preferences, analytics: analytics),
                onDevice: FoundationModelsGiftIntelligenceGateway(analytics: analytics))
        }
        var giftGateway: GiftGateway = SwiftDataGiftGateway(context: store.context)
        var peopleGateway: PeopleGateway = SwiftDataPeopleGateway(context: store.context)
        #if DEBUG
            if let fault = LaunchFault(environment: environment, arguments: arguments) {
                giftGateway = fault.wrap(giftGateway)
                peopleGateway = fault.wrap(peopleGateway)
            }
        #endif
        self.init(
            giftGateway: giftGateway,
            peopleGateway: peopleGateway,
            preferences: preferences,
            intelligence: intelligence,
            launchEnvironment: environment,
            launchArguments: arguments,
            analytics: analytics,
            haptics: haptics
        )
    }

    convenience init(
        store: SwiftDataStore,
        preferences: PreferencesGateway,
        intelligence: GiftIntelligenceGateway,
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        analytics: AnalyticsGateway = NoopAnalyticsGateway(),
        haptics: HapticsGateway = NoopHapticsGateway(),
        giftGateway: GiftGateway? = nil,
        peopleGateway: PeopleGateway? = nil
    ) {
        self.init(
            giftGateway: giftGateway ?? SwiftDataGiftGateway(context: store.context),
            peopleGateway: peopleGateway ?? SwiftDataPeopleGateway(context: store.context),
            preferences: preferences,
            intelligence: intelligence,
            launchEnvironment: launchEnvironment,
            analytics: analytics,
            haptics: haptics
        )
    }

    init(
        giftGateway: GiftGateway,
        peopleGateway: PeopleGateway,
        preferences: PreferencesGateway,
        intelligence: GiftIntelligenceGateway,
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        launchArguments: [String] = [],
        analytics: AnalyticsGateway = NoopAnalyticsGateway(),
        haptics: HapticsGateway = NoopHapticsGateway()
    ) {
        let (giftGateway, peopleGateway) = Self.applyingWriteFailures(
            gifts: giftGateway, people: peopleGateway, launchEnvironment: launchEnvironment)
        let suggestGift = SuggestGiftUseCase(intelligenceGateway: intelligence)
        let createPerson = CreatePersonUseCase(gateway: peopleGateway)

        self.preferences = preferences
        self.analytics = analytics
        self.haptics = haptics
        appDiscovery = AppDiscoveryIndexer(analytics: analytics)
        self.peopleGateway = peopleGateway
        currencyCode = preferences.currencyCode
        router = AppRouter(launchEnvironment: launchEnvironment, analytics: analytics)
        reviewPrompt = Self.makeReviewPrompt(
            preferences: preferences, launchEnvironment: launchEnvironment, launchArguments: launchArguments)
        loadGiftsUseCase = LoadGiftsUseCase(gateway: giftGateway)
        saveGiftUseCase = SaveGiftUseCase(giftGateway: giftGateway, suggestGift: suggestGift)
        deleteGiftUseCase = DeleteGiftUseCase(gateway: giftGateway)
        self.suggestGift = suggestGift
        loadPeopleUseCase = LoadPeopleUseCase(gateway: peopleGateway)
        createPersonUseCase = createPerson
        renamePersonUseCase = RenamePersonUseCase(
            gateway: peopleGateway,
            createPerson: createPerson
        )
        deletePersonUseCase = DeletePersonUseCase(peopleGateway: peopleGateway)

        // Verification launches can start without a viewpoint left over from an earlier run.
        if launchEnvironment["KS_RESET_SELF"] == "1" {
            preferences.setSelfPersonID(nil)
        }
        data.setSelfPerson(preferences.selfPersonID)
        reloadData()
    }

    /// Debug verification launches can make writes fail on purpose (`KS_FAIL_SAVE`, `KS_FAIL_DELETE`) to show
    /// the error states; Release ignores both.
    private static func applyingWriteFailures(
        gifts: GiftGateway, people: PeopleGateway, launchEnvironment: [String: String]
    ) -> (GiftGateway, PeopleGateway) {
        #if DEBUG
            return WriteFailureInjection(launchEnvironment: launchEnvironment).wrap(gifts: gifts, people: people)
        #else
            return (gifts, people)
        #endif
    }

    /// Verification launches never ask for a rating, except `KS_REVIEW_PROMPT=ready`, which starts on
    /// the third day of use so the next new gift (with five gifts in total) shows the request.
    private static func makeReviewPrompt(
        preferences: PreferencesGateway, launchEnvironment: [String: String], launchArguments: [String]
    ) -> ReviewPromptUseCase {
        let isReadyLaunch = launchEnvironment["KS_REVIEW_PROMPT"] == "ready"
        if isReadyLaunch {
            let now = Date()
            preferences.setReviewPromptState(
                ReviewPromptState(
                    activeDays: 3,
                    lastActiveDay: ReviewPromptPolicy.dayKey(for: now, calendar: .autoupdatingCurrent),
                    firstActiveDate: now.addingTimeInterval(-2 * 86_400)))
        }
        return ReviewPromptUseCase(
            preferences: preferences,
            isEnabled: isReadyLaunch
                || !MonitoringConfiguration.isVerificationLaunch(launchEnvironment, arguments: launchArguments))
    }

    /// Loads gifts and people together and publishes them as one snapshot. When either fetch fails,
    /// the previous snapshot and the viewpoint stay as they were, and the screens offer a retry.
    @discardableResult
    func reloadData() -> Bool {
        let gifts: [Gift]
        let people: PeopleSnapshot
        do {
            gifts = try loadGiftsUseCase.execute()
        } catch {
            noteLoadFailure(operation: "load_gifts", error: error)
            return false
        }
        do {
            people = try loadPeopleUseCase.execute()
        } catch {
            noteLoadFailure(operation: "load_people", error: error)
            return false
        }
        data.replaceSnapshot(gifts: gifts, people: people)
        // The viewpoint goes away with its person, including when they were deleted elsewhere.
        if let selfID = data.selfPersonID, !people.people.contains(where: { $0.id == selfID }) {
            setSelfPerson(nil)
        }
        publishAnalyticsContext()
        return true
    }

    /// While the last load failed the screens show older records, so a change loads again first and is
    /// refused when that fails too: it must not be checked against, or write over, newer stored data.
    private func refreshStaleSnapshot() -> Bool {
        guard data.isLoadFailing || !data.hasLoadedSnapshot else { return true }
        return reloadData()
    }

    private func noteLoadFailure(operation: String, error: Error) {
        analytics.report(
            AnalyticsFailure(
                operation: operation, error: error,
                details: ["has_snapshot": .bool(data.hasLoadedSnapshot)]))
        data.noteLoadFailed()
    }

    /// Counts and preferences that travel with every event and crash report.
    private func publishAnalyticsContext() {
        analytics.update(
            AnalyticsContext(
                giftsCount: data.gifts.count,
                peopleCount: data.people.count,
                hasViewpoint: data.selfPersonID != nil,
                currency: currencyCode))
    }

    @discardableResult
    func continueAppDiscovery(_ activity: NSUserActivity) -> Bool {
        // Spotlight already opens this scene. Keep navigation and any draft intact.
        let recognized = AppDiscoveryIndexer.recognizes(activity)
        if recognized { analytics.track(.openedFromSpotlight) }
        return recognized
    }

    /// Saves the gift and says whether it was stored. Only a stored gift counts as saved and plays the
    /// success haptic; after a failure the store is unchanged and the same input can be saved again.
    @discardableResult
    func saveGift(_ input: SaveGiftInput) -> GiftSaveResult {
        guard input.canSave else { return .invalid }
        let mode: GiftSheetMode = input.editingGiftID == nil ? .create : .edit
        analytics.track(.giftSaveAttempted(mode: mode))
        // A save against records that could not be reloaded fails like a refused write: the sheet keeps the
        // draft and shows the error. The load failure itself was already reported by `reloadData`.
        guard refreshStaleSnapshot() else {
            analytics.track(.giftSaveFailed(mode: mode))
            haptics.play(.error)
            noteReviewSetback()
            return .failed
        }
        let gift: Gift
        do {
            guard let saved = try saveGiftUseCase.execute(input) else { return .invalid }
            gift = saved
        } catch {
            analytics.report(AnalyticsFailure(operation: "save_gift", error: error))
            analytics.track(.giftSaveFailed(mode: mode))
            haptics.play(.error)
            noteReviewSetback()
            return .failed
        }
        reloadData()
        analytics.track(.giftSaved(giftSavedProperties(for: gift, input: input)))
        haptics.play(.success)
        if input.editingGiftID == nil,
            reviewPrompt.newGiftSaved(giftsCount: data.gifts.count, peopleCount: data.people.count)
        {
            isReviewRequestPending = true
        }
        return .saved
    }

    // MARK: - App Store rating request

    func sceneBecameActive() {
        isSceneActive = true
        reviewPrompt.appBecameActive()
    }

    /// Control Center, a notification or the app switcher covers the app.
    func sceneBecameInactive() {
        isSceneActive = false
    }

    func sceneEnteredBackground() {
        isSceneActive = false
        reviewPrompt.appEnteredBackground()
        isReviewRequestPending = false
    }

    /// The root view handed the pending moment to the system rating request.
    func reviewRequestPresented() {
        guard isReviewRequestPending else { return }
        isReviewRequestPending = false
        analytics.track(reviewPrompt.recordRequest(giftsCount: data.gifts.count, peopleCount: data.people.count))
    }

    /// A failed save or a deletion: no rating request this session, including one already waiting.
    private func noteReviewSetback() {
        reviewPrompt.noteSetback()
        isReviewRequestPending = false
    }

    /// The moment passed without a request, e.g. the user left Home; a later new gift can try again.
    func reviewRequestSkipped() {
        isReviewRequestPending = false
    }

    private func giftSavedProperties(for gift: Gift, input: SaveGiftInput) -> GiftSavedProperties {
        let direction: GiftSavedDirection
        if let selfID = data.selfPersonID {
            switch GiftDirectionResolver.resolve(giverID: gift.giverID, recipientID: gift.recipientID, relativeTo: selfID) {
            case .received: direction = .received
            case .given: direction = .given
            case nil: direction = .unrelated
            }
        } else {
            direction = .noViewpoint
        }
        let valueSource: GiftValueSource
        if input.valueTouched {
            valueSource = (input.value ?? 0) > 0 ? .user : .none
        } else {
            valueSource = input.estimatedValue == nil ? .none : .estimate
        }
        return GiftSavedProperties(
            mode: input.editingGiftID == nil ? .create : .edit,
            direction: direction,
            iconSource: input.emoji == nil ? .inferred : .user,
            valueSource: valueSource,
            occasion: GiftSavedProperties.occasionLabel(gift.occasion, defaults: AppData.defaultOccasions.map(\.name)),
            paidByYou: gift.paidByYou,
            dateOffset: GiftDateOffset.bucket(for: gift.date, today: AppDate.today),
            giftsCount: data.gifts.count)
    }

    /// Deletes the gift and says whether it is gone; after a failure it is still stored and shown.
    @discardableResult
    func deleteGift(id: String, source: GiftDeletionSource) -> DeletionResult {
        guard refreshStaleSnapshot() else {
            haptics.play(.error)
            noteReviewSetback()
            return .failed
        }
        do {
            try deleteGiftUseCase.execute(id: id)
        } catch {
            analytics.report(AnalyticsFailure(operation: "delete_gift", error: error))
            haptics.play(.error)
            noteReviewSetback()
            reloadData()
            return .failed
        }
        noteReviewSetback()
        reloadData()
        analytics.track(.giftDeleted(source: source, giftsCount: data.gifts.count))
        return .deleted
    }

    /// People ordered for a picker by recent use in `role`; `data.gifts` is reloaded after every save and delete.
    func rankedPeople(for role: PersonPickerRole) -> [Person] {
        rankPickerOptions.rankPeople(data.people, by: role, in: data.gifts)
    }

    var rankedOccasions: [Occasion] {
        rankPickerOptions.rankOccasions(data.occasions, in: data.gifts)
    }

    /// People for an Insights picker: the current choice, then recent picks in that picker, then alphabetical.
    func insightsPickerPeople(for slot: InsightsPickerSlot, selectedID: String?) -> [Person] {
        rankPickerOptions.rankPeople(
            buildInsights.alphabetical(data.people),
            selectedID: selectedID,
            recentIDs: preferences.recentInsightsPicks(for: slot))
    }

    func recordInsightsPick(_ id: String, for slot: InsightsPickerSlot) {
        let recent = rankPickerOptions.recordingPick(id, in: preferences.recentInsightsPicks(for: slot))
        preferences.setRecentInsightsPicks(recent, for: slot)
        analytics.track(.insightsPersonPicked(slot: slot.rawValue))
    }

    /// Creates the person, or returns the existing one with that name without counting a creation.
    func createPerson(name: String, source: PersonCreationSource) -> String? {
        guard refreshStaleSnapshot() else { return nil }
        let id: String?
        do {
            id = try createPersonUseCase.execute(name: name, current: data.peopleSnapshot)
        } catch {
            analytics.report(AnalyticsFailure(operation: "create_person", error: error))
            reloadData()
            return nil
        }
        let existedBefore = id.map { candidate in data.people.contains { $0.id == candidate } } ?? true
        reloadData()
        if id != nil, !existedBefore {
            analytics.track(.personCreated(source: source, peopleCount: data.people.count))
            haptics.play(.success)
        }
        return id
    }

    func renamePerson(id: String, newName: String) {
        guard refreshStaleSnapshot() else { return }
        do {
            try renamePersonUseCase.execute(id: id, newName: newName, current: data.peopleSnapshot)
        } catch {
            if !(error is PersonUpdateError) {
                analytics.report(AnalyticsFailure(operation: "rename_person", error: error))
            }
        }
        reloadData()
    }

    func updatePerson(id: String, name: String, imageData: Data?) throws {
        guard refreshStaleSnapshot() else { throw StaleSnapshotError() }
        let previous = data.people.first { $0.id == id }
        do {
            try renamePersonUseCase.update(id: id, newName: name, imageData: imageData, current: data.peopleSnapshot)
        } catch {
            // A duplicate name is the user's to fix; only unexpected failures are reported.
            if !(error is PersonUpdateError) {
                analytics.report(AnalyticsFailure(operation: "update_person", error: error))
            }
            throw error
        }
        reloadData()
        analytics.track(
            .personUpdated(
                nameChanged: previous?.name != name.trimmingCharacters(in: .whitespaces),
                photo: Self.photoChange(from: previous?.imageData, to: imageData)))
        haptics.play(.success)
    }

    static func photoChange(from previous: Data?, to current: Data?) -> PersonPhotoChange {
        switch (previous, current) {
        case (nil, nil): .unchanged
        case (nil, .some): .added
        case (.some, nil): .removed
        case (.some(let before), .some(let after)): before == after ? .unchanged : .replaced
        }
    }

    /// Deletes the person with their gifts and says whether they are gone; after a failure the person,
    /// their gifts and the viewpoint are unchanged.
    @discardableResult
    func deletePerson(id: String, source: PersonDeletionSource) -> DeletionResult {
        guard refreshStaleSnapshot() else {
            haptics.play(.error)
            noteReviewSetback()
            return .failed
        }
        let giftsRemoved = data.gifts.filter { $0.giverID == id || $0.recipientID == id }.count
        let deleted: Bool
        do {
            try deletePersonUseCase.execute(id: id)
            deleted = true
        } catch {
            analytics.report(AnalyticsFailure(operation: "delete_person", error: error))
            haptics.play(.error)
            deleted = false
        }
        // Removing someone, or failing to, is not a moment to ask for a rating.
        noteReviewSetback()
        // Clear the viewpoint before reloading so a failing reload cannot leave it pointing at a deleted person.
        if deleted, data.isSelf(id) {
            setSelfPerson(nil)
        }
        reloadData()
        guard deleted else { return .failed }
        analytics.track(.personDeleted(source: source, giftsRemoved: giftsRemoved, peopleCount: data.people.count))
        return .deleted
    }

    /// Applies the "This is me" choice made on the person screen.
    func markSelf(_ isSelf: Bool, personID id: String) {
        if isSelf {
            guard !data.isSelf(id) else { return }
            setSelfPerson(id)
        } else if data.isSelf(id) {
            setSelfPerson(nil)
        } else {
            return
        }
        analytics.track(.viewpointChanged(isSet: isSelf))
        publishAnalyticsContext()
    }

    /// Marks exactly one person as the user's viewpoint, or clears it with nil.
    func setSelfPerson(_ id: String?) {
        preferences.setSelfPersonID(id)
        data.setSelfPerson(id)
    }

    func setCurrencyCode(_ currencyCode: String) {
        guard SupportedCurrency(rawValue: currencyCode) != nil, self.currencyCode != currencyCode else { return }
        preferences.setCurrencyCode(currencyCode)
        self.currencyCode = currencyCode
        analytics.track(.currencyChanged(currency: currencyCode))
        publishAnalyticsContext()
    }
}

/// A change was refused because the records on screen could not be brought up to date first.
struct StaleSnapshotError: Error {}
