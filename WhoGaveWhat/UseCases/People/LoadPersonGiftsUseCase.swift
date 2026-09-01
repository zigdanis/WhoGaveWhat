struct LoadPersonGiftsUseCase {
    func execute(personID: String, gifts: [Gift]) -> [Gift] {
        gifts
            .filter { $0.giverID == personID || $0.recipientID == personID }
            .sorted(by: Gift.newestFirst)
    }
}
