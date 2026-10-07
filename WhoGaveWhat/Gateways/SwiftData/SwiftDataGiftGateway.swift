import Foundation
import SwiftData

@MainActor
final class SwiftDataGiftGateway: GiftGateway {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func loadGifts() throws -> [Gift] {
        let descriptor = FetchDescriptor<StoredGift>(sortBy: [
            SortDescriptor(\StoredGift.date, order: .reverse),
            SortDescriptor(\StoredGift.createdAt, order: .reverse)
        ])
        return try context.fetch(descriptor).map(Gift.init)
    }

    func save(_ gift: Gift) throws {
        guard gift.giverID != gift.recipientID else {
            throw SwiftDataPersistenceError.identicalGiftEndpoints(id: gift.giverID)
        }
        guard let giver = try fetchPerson(id: gift.giverID) else {
            throw SwiftDataPersistenceError.missingPerson(endpoint: .giver, id: gift.giverID)
        }
        guard let recipient = try fetchPerson(id: gift.recipientID) else {
            throw SwiftDataPersistenceError.missingPerson(endpoint: .recipient, id: gift.recipientID)
        }

        let storedGift: StoredGift
        if let existing = try fetchGift(id: gift.id) {
            storedGift = existing
        } else {
            storedGift = StoredGift(
                id: gift.id,
                emoji: gift.emoji,
                name: gift.name,
                giver: giver,
                recipient: recipient,
                paidByYou: gift.paidByYou,
                occasion: gift.occasion,
                date: gift.date,
                value: gift.value,
                createdAt: gift.createdAt
            )
            context.insert(storedGift)
        }
        storedGift.emoji = gift.emoji
        storedGift.name = gift.name
        storedGift.giver = giver
        storedGift.recipient = recipient
        storedGift.paidByYou = gift.paidByYou
        storedGift.occasion = gift.occasion
        storedGift.date = gift.date
        storedGift.value = gift.value
        storedGift.createdAt = gift.createdAt
        try saveContext()
    }

    func deleteGift(id: String) throws {
        if let gift = try fetchGift(id: id) {
            context.delete(gift)
            try saveContext()
        }
    }

    private func fetchGift(id: String) throws -> StoredGift? {
        let requestedID = id
        var descriptor = FetchDescriptor<StoredGift>(
            predicate: #Predicate { gift in
                gift.id == requestedID
            })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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

private extension Gift {
    init(_ storedGift: StoredGift) {
        self.init(
            id: storedGift.id,
            emoji: storedGift.emoji,
            name: storedGift.name,
            direction: GiftDirectionResolver.resolve(
                giverID: storedGift.giver.id,
                giverRole: PersonRole(rawValue: storedGift.giver.roleRawValue) ?? .contact,
                recipientID: storedGift.recipient.id,
                recipientRole: PersonRole(rawValue: storedGift.recipient.roleRawValue) ?? .contact
            ),
            giverID: storedGift.giver.id,
            recipientID: storedGift.recipient.id,
            paidByYou: storedGift.paidByYou,
            occasion: storedGift.occasion,
            date: storedGift.date,
            value: storedGift.value,
            createdAt: storedGift.createdAt
        )
    }
}
