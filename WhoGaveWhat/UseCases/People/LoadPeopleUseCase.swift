@MainActor
struct LoadPeopleUseCase {
    let gateway: PeopleGateway

    func execute() throws -> PeopleSnapshot {
        try gateway.loadPeople()
    }
}
