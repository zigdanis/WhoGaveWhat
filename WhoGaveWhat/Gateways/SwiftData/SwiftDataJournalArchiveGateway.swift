import Foundation
import SwiftData

@MainActor
final class SwiftDataJournalArchiveGateway: JournalArchiveGateway {
    private let context: ModelContext
    /// The currency a gift saved before per-gift currencies has, until the store has saved it on the gift.
    private let legacyGiftCurrency: SupportedCurrency?
    /// Saves a restore; tests replace it to make the save fail.
    private let save: (ModelContext) throws -> Void

    init(
        context: ModelContext,
        legacyGiftCurrency: SupportedCurrency? = nil,
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.legacyGiftCurrency = legacyGiftCurrency
        self.save = save
    }

    func loadArchive() throws -> (people: [DataBackup.Person], gifts: [DataBackup.Gift]) {
        let people = try context.fetch(
            FetchDescriptor<StoredPerson>(sortBy: [SortDescriptor(\StoredPerson.sortIndex)]))
        let gifts = try context.fetch(
            FetchDescriptor<StoredGift>(sortBy: [
                SortDescriptor(\StoredGift.createdAt), SortDescriptor(\StoredGift.id)
            ]))
        return (
            people.map { person in
                DataBackup.Person(
                    id: person.id, name: person.name, colorHex: UInt(bitPattern: Int(person.colorHex)),
                    sortIndex: person.sortIndex, photo: person.imageData)
            },
            try gifts.map { gift in
                // Never fall back to the current default currency: that would relabel the amount.
                let currency: SupportedCurrency? =
                    if let code = gift.currencyCode {
                        SupportedCurrency(rawValue: code)
                    } else {
                        legacyGiftCurrency
                    }
                guard let currency else { throw SwiftDataPersistenceError.missingCurrency(giftID: gift.id) }
                return DataBackup.Gift(
                    id: gift.id, emoji: gift.emoji, name: gift.name, giverID: gift.giver.id,
                    recipientID: gift.recipient.id, paidByYou: gift.paidByYou, occasion: gift.occasion,
                    date: gift.date, value: gift.value, currency: currency, createdAt: gift.createdAt,
                    emojiPickedByUser: gift.emojiPickedByUser, lastSavedAt: gift.lastSavedAt)
            }
        )
    }

    @discardableResult
    func restore(_ backup: DataBackup) throws -> DataRestoreSummary {
        let backup = try backup.validated()
        let storedPeople = try context.fetch(FetchDescriptor<StoredPerson>())
        let storedGiftIDs = Set(try context.fetch(FetchDescriptor<StoredGift>()).map(\.id))
        var summary = DataRestoreSummary()
        summary.restoredIntoEmptyJournal = storedPeople.isEmpty && storedGiftIDs.isEmpty

        var peopleByID = Dictionary(storedPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Names identify people in the app (see `CreatePersonUseCase`), so a backup person with the name
        // of someone already here is that person, whatever id each install gave them.
        var peopleByName = Dictionary(
            storedPeople.map { (Self.nameKey($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        var nextSortIndex = (storedPeople.map(\.sortIndex).max() ?? -1) + 1
        var restoredPeople: [String: StoredPerson] = [:]

        // Backup order decides, but places are renumbered from here, so no stored sort index comes from the file.
        for person in backup.people.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            if let existing = peopleByID[person.id] ?? peopleByName[Self.nameKey(person.name)] {
                restoredPeople[person.id] = existing
                summary.peopleMatched += 1
                continue
            }
            let sortIndex = nextSortIndex
            nextSortIndex += 1
            let stored = StoredPerson(
                id: person.id, name: person.name, colorHex: Int64(Int(bitPattern: person.colorHex)),
                sortIndex: sortIndex, imageData: person.photo)
            context.insert(stored)
            peopleByID[person.id] = stored
            peopleByName[Self.nameKey(person.name)] = stored
            restoredPeople[person.id] = stored
            summary.peopleAdded += 1
        }

        summary.restoredSelfPersonID = backup.selfPersonID.flatMap { restoredPeople[$0]?.id }

        for gift in backup.gifts {
            guard !storedGiftIDs.contains(gift.id) else {
                summary.giftsAlreadyHere += 1
                continue
            }
            // Validation guarantees both people; two backup people can match one person here, and a gift
            // from someone to themselves cannot be stored.
            guard let giver = restoredPeople[gift.giverID], let recipient = restoredPeople[gift.recipientID],
                giver.id != recipient.id
            else {
                summary.giftsWithoutPlace += 1
                continue
            }
            context.insert(
                StoredGift(
                    id: gift.id, emoji: gift.emoji, name: gift.name, giver: giver, recipient: recipient,
                    paidByYou: gift.paidByYou, occasion: gift.occasion, date: gift.date, value: gift.value,
                    createdAt: gift.createdAt, emojiPickedByUser: gift.emojiPickedByUser,
                    lastSavedAt: gift.lastSavedAt, currencyCode: gift.currency.code))
            summary.giftsAdded += 1
        }

        guard summary.addedAnything else { return summary }
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
        return summary
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive], locale: nil)
    }
}
