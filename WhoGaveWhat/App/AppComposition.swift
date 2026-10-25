import Foundation
import Observation

@MainActor
@Observable
final class AppComposition {
    let router: AppRouter
    let appDiscovery: AppDiscoveryIndexer
    let data = AppData()
    let analytics: AnalyticsGateway
    private(set) var currencyCode: String
    private(set) var isAnalyticsEnabled: Bool
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

    convenience init(store: SwiftDataStore, preferences: UserDefaultsPreferencesGateway, analytics: AnalyticsGateway) {
        let environment = ProcessInfo.processInfo.environment
        let cloud: GiftIntelligenceGateway
        if environment["KS_CLOUD_ICONS"] == "stub" {
            cloud = StubCloudGiftIconGateway()
        } else {
            cloud = CloudGiftIconGateway(preferences: preferences, analytics: analytics)
        }
        self.init(
            store: store,
            preferences: preferences,
            intelligence: PreferredGiftIntelligenceGateway(
                preferences: preferences,
                cloud: cloud,
                onDevice: FoundationModelsGiftIntelligenceGateway(analytics: analytics)
            ),
            launchEnvironment: environment,
            analytics: analytics
        )
    }

    init(
        store: SwiftDataStore,
        preferences: PreferencesGateway,
        intelligence: GiftIntelligenceGateway,
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        analytics: AnalyticsGateway = NoopAnalyticsGateway()
    ) {
        let giftGateway = SwiftDataGiftGateway(context: store.context)
        let peopleGateway = SwiftDataPeopleGateway(context: store.context)
        let suggestGift = SuggestGiftUseCase(intelligenceGateway: intelligence)
        let createPerson = CreatePersonUseCase(gateway: peopleGateway)

        self.preferences = preferences
        self.analytics = analytics
        appDiscovery = AppDiscoveryIndexer(analytics: analytics)
        if let rawConsent = launchEnvironment["KS_CLOUD_ICON_CONSENT"],
            let consent = CloudIconConsent(rawValue: rawConsent)
        {
            preferences.setCloudIconConsent(consent)
        }
        self.peopleGateway = peopleGateway
        currencyCode = preferences.currencyCode
        isAnalyticsEnabled = preferences.analyticsEnabled
        router = AppRouter(launchEnvironment: launchEnvironment, analytics: analytics)
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

    func reloadData() {
        do {
            data.replaceGifts(try loadGiftsUseCase.execute())
        } catch {
            analytics.report(AnalyticsFailure(operation: "load_gifts", error: error))
        }
        do {
            let people = try loadPeopleUseCase.execute()
            data.replacePeople(people)
            // The viewpoint goes away with its person, including when they were deleted elsewhere.
            if let selfID = data.selfPersonID, !people.people.contains(where: { $0.id == selfID }) {
                setSelfPerson(nil)
            }
        } catch {
            analytics.report(AnalyticsFailure(operation: "load_people", error: error))
        }
        publishAnalyticsContext()
    }

    /// Counts and preferences that travel with every event and crash report.
    private func publishAnalyticsContext() {
        analytics.update(
            AnalyticsContext(
                giftsCount: data.gifts.count,
                peopleCount: data.people.count,
                hasViewpoint: data.selfPersonID != nil,
                currency: currencyCode,
                cloudIcons: preferences.cloudIconConsent.rawValue))
    }

    @discardableResult
    func continueAppDiscovery(_ activity: NSUserActivity) -> Bool {
        // Spotlight already opens this scene. Keep navigation and any draft intact.
        let recognized = AppDiscoveryIndexer.recognizes(activity)
        if recognized { analytics.track(.openedFromSpotlight) }
        return recognized
    }

    /// Saves the gift and reports whether it was stored.
    @discardableResult
    func saveGift(_ input: SaveGiftInput) -> Bool {
        let gift: Gift?
        do {
            gift = try saveGiftUseCase.execute(input)
        } catch {
            analytics.report(AnalyticsFailure(operation: "save_gift", error: error))
            return false
        }
        guard let gift else { return false }
        reloadData()
        analytics.track(.giftSaved(giftSavedProperties(for: gift, input: input)))
        return true
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

    func deleteGift(id: String, source: GiftDeletionSource) {
        do {
            try deleteGiftUseCase.execute(id: id)
        } catch {
            analytics.report(AnalyticsFailure(operation: "delete_gift", error: error))
            reloadData()
            return
        }
        reloadData()
        analytics.track(.giftDeleted(source: source, giftsCount: data.gifts.count))
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
        }
        return id
    }

    func renamePerson(id: String, newName: String) {
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
    }

    static func photoChange(from previous: Data?, to current: Data?) -> PersonPhotoChange {
        switch (previous, current) {
        case (nil, nil): .unchanged
        case (nil, .some): .added
        case (.some, nil): .removed
        case (.some(let before), .some(let after)): before == after ? .unchanged : .replaced
        }
    }

    func deletePerson(id: String, source: PersonDeletionSource) {
        let giftsRemoved = data.gifts.filter { $0.giverID == id || $0.recipientID == id }.count
        let deleted: Bool
        do {
            try deletePersonUseCase.execute(id: id)
            deleted = true
        } catch {
            analytics.report(AnalyticsFailure(operation: "delete_person", error: error))
            deleted = false
        }
        // Clear the viewpoint before reloading so a failing reload cannot leave it pointing at a deleted person.
        if deleted, data.isSelf(id) {
            setSelfPerson(nil)
        }
        reloadData()
        if deleted {
            analytics.track(.personDeleted(source: source, giftsRemoved: giftsRemoved, peopleCount: data.people.count))
        }
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

    var cloudIconConsent: CloudIconConsent { preferences.cloudIconConsent }

    func setCloudIconConsent(_ consent: CloudIconConsent, source: ConsentSource = .settings) {
        guard preferences.cloudIconConsent != consent else { return }
        preferences.setCloudIconConsent(consent)
        if consent != .undecided {
            analytics.track(.cloudIconsConsentChanged(allowed: consent == .allowed, source: source))
        }
        publishAnalyticsContext()
    }

    /// The Settings switch for usage events and crash reports. Turning it off is the last thing sent.
    func setAnalyticsEnabled(_ enabled: Bool) {
        guard isAnalyticsEnabled != enabled else { return }
        isAnalyticsEnabled = enabled
        preferences.setAnalyticsEnabled(enabled)
        if enabled {
            analytics.setEnabled(true)
            analytics.track(.analyticsConsentChanged(enabled: true))
            publishAnalyticsContext()
        } else {
            analytics.track(.analyticsConsentChanged(enabled: false))
            analytics.setEnabled(false)
        }
    }
}
