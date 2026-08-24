@MainActor
struct DeletePersonUseCase {
    let peopleGateway: PeopleGateway
    let giftGateway: GiftGateway

    func canDelete(id: String) -> Bool { id != "you" }

    func execute(id: String) throws {
        guard canDelete(id: id) else { return }
        try giftGateway.deleteGifts(involving: id)
        try peopleGateway.deletePerson(id: id)
    }
}
