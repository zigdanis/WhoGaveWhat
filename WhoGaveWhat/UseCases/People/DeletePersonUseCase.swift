@MainActor
struct DeletePersonUseCase {
    let peopleGateway: PeopleGateway

    func canDelete(id: String) -> Bool { true }

    func execute(id: String) throws {
        try peopleGateway.deletePerson(id: id)
    }
}
