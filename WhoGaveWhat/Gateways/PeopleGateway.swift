@MainActor
protocol PeopleGateway: AnyObject {
    func loadPeople() throws -> PeopleSnapshot
    func createPerson(
        id: String,
        name: String,
        colorHex: UInt,
        isFamily: Bool,
        sortIndex: Int
    ) throws
    func renamePerson(id: String, name: String) throws
    func deletePerson(id: String) throws
}
