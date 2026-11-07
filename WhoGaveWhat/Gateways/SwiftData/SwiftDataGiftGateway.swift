import Foundation
import SwiftData

@MainActor
final class SwiftDataGiftGateway: GiftGateway {
    private let context: ModelContext
    /// The currency a gift saved before per-gift currencies has, until the store has saved it on the gift.
    private let legacyGiftCurrency: SupportedCurrency?

    init(context: ModelContext, legacyGiftCurrency: SupportedCurrency? = nil) {
        self.context = context
        self.legacyGiftCurrency = legacyGiftCurrency
    }

    func loadGifts() throws -> [Gift] {
        let descriptor = FetchDescriptor<StoredGift>(sortBy: [
            SortDescriptor(\StoredGift.date, order: .reverse),
            SortDescriptor(\StoredGift.createdAt, order: .reverse)
        ])
        return try context.fetch(descriptor).map { try Gift($0, legacyCurrency: legacyGiftCurrency) }
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
                createdAt: gift.createdAt,
                emojiPickedByUser: gift.emojiPickedByUser,
                lastSavedAt: gift.lastSavedAt,
                currencyCode: gift.currency.code
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
        storedGift.currencyCode = gift.currency.code
        storedGift.createdAt = gift.createdAt
        storedGift.emojiPickedByUser = gift.emojiPickedByUser
        storedGift.lastSavedAt = gift.lastSavedAt
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
    /// `legacyCurrency` applies only to a gift with no stored currency, one saved before gifts had their own.
    init(_ storedGift: StoredGift, legacyCurrency: SupportedCurrency?) throws {
        // Never fall back to the current default currency: that would relabel the amount.
        let currency =
            if let code = storedGift.currencyCode {
                SupportedCurrency(rawValue: code)
            } else {
                legacyCurrency
            }
        guard let currency else {
            throw SwiftDataPersistenceError.missingCurrency(giftID: storedGift.id)
        }
        self.init(
            id: storedGift.id,
            emoji: storedGift.emoji,
            name: storedGift.name,
            giverID: storedGift.giver.id,
            recipientID: storedGift.recipient.id,
            paidByYou: storedGift.paidByYou,
            occasion: storedGift.occasion,
            date: storedGift.date,
            value: storedGift.value,
            currency: currency,
            createdAt: storedGift.createdAt,
            emojiPickedByUser: storedGift.emojiPickedByUser,
            lastSavedAt: storedGift.lastSavedAt
        )
    }
}
