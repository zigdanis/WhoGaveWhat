@MainActor
struct DeletePersonUseCase {
    let peopleGateway: PeopleGateway

    func canDelete(id: String) -> Bool { id != "you" }

    func execute(id: String) throws {
        guard canDelete(id: id) else { return }
        try peopleGateway.deletePerson(id: id)
    }
}
