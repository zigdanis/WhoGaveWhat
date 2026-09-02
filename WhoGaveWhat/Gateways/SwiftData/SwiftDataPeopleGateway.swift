import Foundation
import SwiftData

@MainActor
final class SwiftDataPeopleGateway: PeopleGateway {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func loadPeople() throws -> PeopleSnapshot {
        let descriptor = FetchDescriptor<StoredPerson>(sortBy: [
            SortDescriptor(\StoredPerson.roleRawValue),
            SortDescriptor(\StoredPerson.sortIndex),
        ])
        return PeopleSnapshot(people: try context.fetch(descriptor).map(Person.init))
    }

    func createPerson(
        id: String,
        name: String,
        colorHex: UInt,
        role: PersonRole,
        sortIndex: Int
    ) throws {
        let person = StoredPerson(
            id: id,
            name: name,
            colorHex: Int64(colorHex),
            roleRawValue: role.rawValue,
            sortIndex: sortIndex
        )
        context.insert(person)
        try saveContext()
    }

    func renamePerson(id: String, name: String) throws {
        if let person = try fetchPerson(id: id) {
            person.name = name
            try saveContext()
        }
    }

    func deletePerson(id: String) throws {
        if let person = try fetchPerson(id: id) {
            context.delete(person)
            try saveContext()
        }
    }

    private func fetchPerson(id: String) throws -> StoredPerson? {
        let requestedID = id
        var descriptor = FetchDescriptor<StoredPerson>(predicate: #Predicate { person in
            person.id == requestedID
        })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func saveContext() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

private extension Person {
    init(_ storedPerson: StoredPerson) {
        self.init(
            id: storedPerson.id,
            name: storedPerson.name,
            colorHex: UInt(bitPattern: Int(storedPerson.colorHex)),
            role: PersonRole(rawValue: storedPerson.roleRawValue) ?? .contact
        )
    }
}
