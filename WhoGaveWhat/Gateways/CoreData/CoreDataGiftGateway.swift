import CoreData
import Foundation

@MainActor
final class CoreDataGiftGateway: GiftGateway {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func loadGifts() throws -> [Gift] {
        let request = CDGift.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return try context.fetch(request).map(Gift.init)
    }

    func save(_ gift: Gift) throws {
        let managedGift = try fetchGift(id: gift.id) ?? CDGift(context: context)
        managedGift.id = gift.id
        managedGift.emoji = gift.emoji
        managedGift.name = gift.name
        managedGift.flow = gift.flow.rawValue
        managedGift.person = try fetchPerson(id: gift.personId)
        managedGift.member = try fetchPerson(id: gift.memberId)
        managedGift.paidByYou = gift.paidByYou
        managedGift.celebration = gift.celebration
        managedGift.date = gift.date
        managedGift.value = gift.value
        try saveContext()
    }

    func deleteGift(id: String) throws {
        if let gift = try fetchGift(id: id) {
            context.delete(gift)
            try saveContext()
        }
    }

    func deleteGifts(involving personID: String) throws {
        let request = CDGift.fetchRequest()
        request.predicate = NSPredicate(
            format: "person.id == %@ OR member.id == %@",
            personID,
            personID
        )
        for gift in try context.fetch(request) {
            context.delete(gift)
        }
        try saveContext()
    }

    private func fetchGift(id: String) throws -> CDGift? {
        let request = CDGift.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
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

private extension Gift {
    init(_ managedGift: CDGift) {
        self.init(
            id: managedGift.id ?? UUID().uuidString,
            emoji: managedGift.emoji ?? "🎁",
            name: managedGift.name ?? "",
            flow: GiftFlow(rawValue: managedGift.flow ?? "received") ?? .received,
            personId: managedGift.person?.id ?? "",
            memberId: managedGift.member?.id ?? "you",
            paidByYou: managedGift.paidByYou,
            celebration: managedGift.celebration ?? "",
            date: managedGift.date ?? AppDate.today,
            value: managedGift.value
        )
    }
}
