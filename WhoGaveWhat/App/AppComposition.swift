import Observation

@MainActor
@Observable
final class AppComposition {
    let router: AppRouter
    let data = AppData()

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

    convenience init(stack: CoreDataStack) {
        self.init(
            stack: stack,
            preferences: UserDefaultsPreferencesGateway(),
            intelligence: FoundationModelsGiftIntelligenceGateway()
        )
    }

    init(
        stack: CoreDataStack,
        preferences: PreferencesGateway,
        intelligence: GiftIntelligenceGateway
    ) {
        let context = stack.container.viewContext
        let giftGateway = CoreDataGiftGateway(context: context)
        let peopleGateway = CoreDataPeopleGateway(context: context)
        let suggestGift = SuggestGiftUseCase(intelligenceGateway: intelligence)
        let createPerson = CreatePersonUseCase(gateway: peopleGateway)

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
        deletePersonUseCase = DeletePersonUseCase(
            peopleGateway: peopleGateway,
            giftGateway: giftGateway
        )
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
}
