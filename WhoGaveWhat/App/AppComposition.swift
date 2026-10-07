import Observation

@MainActor
@Observable
final class AppComposition {
    let router: AppRouter
    let data = AppData()
    private(set) var currencyCode: String
    private let preferences: PreferencesGateway

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

        reloadData()
    }

    func reloadData() {
        if let gifts = try? loadGiftsUseCase.execute() {
            data.replaceGifts(gifts)
        }
        if let people = try? loadPeopleUseCase.execute() {
            data.replacePeople(people)
        }
    }

    func saveGift(_ input: SaveGiftInput) {
        guard (try? saveGiftUseCase.execute(input, householdIDs: data.householdIDs)) != nil else { return }
        reloadData()
    }

    func deleteGift(id: String) {
        try? deleteGiftUseCase.execute(id: id)
        reloadData()
    }

    func createPerson(name: String, isFamily: Bool) -> String? {
        let id = try? createPersonUseCase.execute(
            name: name,
            isFamily: isFamily,
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

    func deletePerson(id: String) {
        try? deletePersonUseCase.execute(id: id)
        reloadData()
    }

    func setCurrencyCode(_ currencyCode: String) {
        guard self.currencyCode != currencyCode else { return }
        preferences.setCurrencyCode(currencyCode)
        self.currencyCode = currencyCode
    }
}
