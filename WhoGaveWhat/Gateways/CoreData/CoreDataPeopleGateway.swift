import CoreData
import Foundation

@MainActor
final class CoreDataPeopleGateway: PeopleGateway {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func loadPeople() throws -> PeopleSnapshot {
        let request = CDPerson.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true)]
        let records = try context.fetch(request)
        return PeopleSnapshot(
            members: records.filter(\.isFamily).map(HouseholdMember.init),
            people: records.filter { !$0.isFamily }.map(Person.init)
        )
    }

    func createPerson(
        id: String,
        name: String,
        colorHex: UInt,
        isFamily: Bool,
        sortIndex: Int
    ) throws {
        let person = CDPerson(context: context)
        person.id = id
        person.name = name
        person.colorHex = Int64(colorHex)
        person.isFamily = isFamily
        person.sortIndex = Int64(sortIndex)
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

    private func fetchPerson(id: String) throws -> CDPerson? {
        let request = CDPerson.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
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

private extension HouseholdMember {
    init(_ managedPerson: CDPerson) {
        self.init(
            id: managedPerson.id ?? "",
            name: managedPerson.name ?? "",
            colorHex: UInt(bitPattern: Int(managedPerson.colorHex))
        )
    }
}

private extension Person {
    init(_ managedPerson: CDPerson) {
        self.init(
            id: managedPerson.id ?? "",
            name: managedPerson.name ?? "",
            colorHex: UInt(bitPattern: Int(managedPerson.colorHex))
        )
    }
}
