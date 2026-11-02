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
            SortDescriptor(\StoredPerson.sortIndex)
        ])
        return PeopleSnapshot(people: try context.fetch(descriptor).map(Person.init))
    }

    func createPerson(
        id: String,
        name: String,
        colorHex: UInt,
        sortIndex: Int
    ) throws {
        let person = StoredPerson(
            id: id,
            name: name,
            colorHex: Int64(colorHex),
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

    func updatePerson(id: String, name: String, imageData: Data?) throws {
        guard let person = try fetchPerson(id: id) else { return }
        let oldName = person.name
        let oldImageData = person.imageData
        person.name = name
        person.imageData = imageData
        do {
            try context.save()
        } catch {
            person.name = oldName
            person.imageData = oldImageData
            context.rollback()
            throw error
        }
    }

    func deletePerson(id: String) throws {
        if let person = try fetchPerson(id: id) {
            // iOS 18 SwiftData traps ("an appropriate default value is not configured") when
            // deleting a person still has to detach it from a gift's non-optional giver or
            // recipient. So there the gifts are deleted first and the context processes those
            // deletions before the person goes. processPendingChanges writes nothing to the
            // store, so the one save below still commits or rolls back all of it.
            if #unavailable(iOS 26.0) {
                let gifts = person.giftsGiven + person.giftsReceived
                if !gifts.isEmpty {
                    gifts.forEach(context.delete)
                    context.processPendingChanges()
                }
            }
            context.delete(person)
            try saveContext()
        }
    }

    private func fetchPerson(id: String) throws -> StoredPerson? {
        let requestedID = id
        var descriptor = FetchDescriptor<StoredPerson>(
            predicate: #Predicate { person in
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
            imageData: storedPerson.imageData
        )
    }
}
