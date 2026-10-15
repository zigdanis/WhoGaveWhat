import Foundation
import Observation

@MainActor
@Observable
final class AppComposition {
    let router: AppRouter
    let appDiscovery = AppDiscoveryIndexer()
    let data = AppData()
    private(set) var currencyCode: String
    private let preferences: PreferencesGateway
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
        self.init(
            store: store,
            preferences: UserDefaultsPreferencesGateway(),
            intelligence: FoundationModelsGiftIntelligenceGateway()
        )
    }

    init(
        store: SwiftDataStore,
        preferences: PreferencesGateway,
        intelligence: GiftIntelligenceGateway
    ) {
        let giftGateway = SwiftDataGiftGateway(context: store.context)
        let peopleGateway = SwiftDataPeopleGateway(context: store.context)
        let suggestGift = SuggestGiftUseCase(intelligenceGateway: intelligence)
        let createPerson = CreatePersonUseCase(gateway: peopleGateway)

        self.preferences = preferences
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
        try? deletePersonUseCase.execute(id: id)
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
}
