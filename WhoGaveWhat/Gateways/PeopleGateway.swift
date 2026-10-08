import Foundation

@MainActor
enum PersonUpdateError: Error {
    case duplicateName
}

@MainActor
protocol PeopleGateway: AnyObject {
    func loadPeople() throws -> PeopleSnapshot
    func createPerson(
        id: String,
        name: String,
        colorHex: UInt,
        role: PersonRole,
        sortIndex: Int
    ) throws
    func renamePerson(id: String, name: String) throws
    func updatePerson(id: String, name: String, imageData: Data?) throws
    func deletePerson(id: String) throws
}
