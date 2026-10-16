import Foundation
import Observation

@MainActor
@Observable
final class AppComposition {
    let router: AppRouter
    let appDiscovery = AppDiscoveryIndexer()
    let data = AppData()
    private(set) var currencyCode: String
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
    let completeOnboarding: CompleteOnboardingUseCase

    convenience init(store: SwiftDataStore) {
        let preferences = UserDefaultsPreferencesGateway()
        let environment = ProcessInfo.processInfo.environment
        let cloud: GiftIntelligenceGateway
        if environment["KS_CLOUD_ICONS"] == "stub" {
            cloud = StubCloudGiftIconGateway()
        } else {
            cloud = CloudGiftIconGateway(preferences: preferences)
        }
        self.init(
            store: store,
            preferences: preferences,
            intelligence: PreferredGiftIntelligenceGateway(
                preferences: preferences,
                cloud: cloud,
                onDevice: FoundationModelsGiftIntelligenceGateway()
            ),
            launchEnvironment: environment
        )
    }

    init(
        store: SwiftDataStore,
        preferences: PreferencesGateway,
        intelligence: GiftIntelligenceGateway,
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let giftGateway = SwiftDataGiftGateway(context: store.context)
        let peopleGateway = SwiftDataPeopleGateway(context: store.context)
        let suggestGift = SuggestGiftUseCase(intelligenceGateway: intelligence)
        let createPerson = CreatePersonUseCase(gateway: peopleGateway)

        self.preferences = preferences
        if let rawConsent = launchEnvironment["KS_CLOUD_ICON_CONSENT"],
            let consent = CloudIconConsent(rawValue: rawConsent)
        {
            preferences.setCloudIconConsent(consent)
        }
        self.peopleGateway = peopleGateway
        currencyCode = preferences.currencyCode
        router = AppRouter(didCompleteOnboarding: preferences.didCompleteOnboarding)
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
        completeOnboarding = CompleteOnboardingUseCase(preferencesGateway: preferences)

        // Verification launches can start without a viewpoint left over from an earlier run.
        if launchEnvironment["KS_RESET_SELF"] == "1" {
            preferences.setSelfPersonID(nil)
        }
        data.setSelfPerson(preferences.selfPersonID)
        reloadData()
    }

    func reloadData() {
        if let gifts = try? loadGiftsUseCase.execute() {
            data.replaceGifts(gifts)
        }
        if let people = try? loadPeopleUseCase.execute() {
            data.replacePeople(people)
            // The viewpoint goes away with its person, including when they were deleted elsewhere.
            if let selfID = data.selfPersonID, !people.people.contains(where: { $0.id == selfID }) {
                setSelfPerson(nil)
            }
        }
    }

    @discardableResult
    func continueAppDiscovery(_ activity: NSUserActivity) -> Bool {
        // Spotlight already opens this scene. Keep onboarding, navigation and any draft intact.
        AppDiscoveryIndexer.recognizes(activity)
    }

    func saveGift(_ input: SaveGiftInput) {
        guard (try? saveGiftUseCase.execute(input)) != nil else { return }
        reloadData()
    }

    func deleteGift(id: String) {
        try? deleteGiftUseCase.execute(id: id)
        reloadData()
    }

    func createPerson(name: String) -> String? {
        let id = try? createPersonUseCase.execute(
            name: name,
            current: data.peopleSnapshot
        )
        reloadData()
        return id
    }

    func renamePerson(id: String, newName: String) {
        try? renamePersonUseCase.execute(
            id: id,
            newName: newName,
            current: data.peopleSnapshot
        )
        reloadData()
    }

    func updatePerson(id: String, name: String, imageData: Data?) throws {
        try renamePersonUseCase.update(
            id: id, newName: name, imageData: imageData, current: data.peopleSnapshot)
        reloadData()
    }

    func deletePerson(id: String) {
        let deleted = (try? deletePersonUseCase.execute(id: id)) != nil
        // Clear the viewpoint before reloading so a failing reload cannot leave it pointing at a deleted person.
        if deleted, data.isSelf(id) {
            setSelfPerson(nil)
        }
        reloadData()
    }

    /// Applies the "This is me" choice made on the person screen.
    func markSelf(_ isSelf: Bool, personID id: String) {
        if isSelf {
            setSelfPerson(id)
        } else if data.isSelf(id) {
            setSelfPerson(nil)
        }
    }

    /// Marks exactly one person as the user's viewpoint, or clears it with nil.
    func setSelfPerson(_ id: String?) {
        preferences.setSelfPersonID(id)
        data.setSelfPerson(id)
    }

    func setCurrencyCode(_ currencyCode: String) {
        guard self.currencyCode != currencyCode else { return }
        preferences.setCurrencyCode(currencyCode)
        self.currencyCode = currencyCode
    }

    var cloudIconConsent: CloudIconConsent { preferences.cloudIconConsent }

    func setCloudIconConsent(_ consent: CloudIconConsent) {
        preferences.setCloudIconConsent(consent)
    }
}
