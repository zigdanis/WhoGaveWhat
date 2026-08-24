struct LoadPersonGiftsUseCase {
    func execute(personID: String, isHouseholdMember: Bool, gifts: [Gift]) -> [Gift] {
        gifts
            .filter { isHouseholdMember ? $0.memberId == personID : $0.personId == personID }
            .sorted(by: Gift.newestFirst)
    }
}
