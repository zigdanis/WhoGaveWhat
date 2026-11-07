// Writes one store fixture with the SwiftData model code of an earlier build.
//
// generate.py compiles this file together with that build's `SwiftDataModels.swift`, taken
// unchanged from Git, and sets one `-D` flag for every attribute the build's schema had:
// HAS_ROLE, HAS_IMAGE_DATA, HAS_EMOJI_PICKED_BY_USER, HAS_LAST_SAVED_AT, HAS_CURRENCY_CODE. A later schema
// version adds its own flag here and in generate.py.
//
// Usage: FixtureWriter MANIFEST.json OUTPUT.store

import Foundation
import SwiftData

struct FixtureDataset: Decodable {
    struct Person: Decodable {
        let id: String
        let name: String
        let colorHex: Int64
        let sortIndex: Int
        let role: String?
        let imageBase64: String?
    }

    struct Gift: Decodable {
        let id: String
        let emoji: String
        let name: String
        let giverID: String
        let recipientID: String
        let paidByYou: Bool
        let occasion: String
        let date: Date
        let value: Double
        let createdAt: Date
        let emojiPickedByUser: Bool?
        let lastSavedAt: Date?
        let currencyCode: String?
    }

    let people: [Person]
    let gifts: [Gift]
}

struct FixtureManifest: Decodable {
    let dataset: FixtureDataset
}

enum FixtureWriterError: Error {
    case usage
    case unknownPerson(String)
}

@main
struct FixtureWriter {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else { throw FixtureWriterError.usage }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            FixtureManifest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        let output = URL(fileURLWithPath: arguments[2])

        // The app's store name and schema, written to an explicit file instead of Application Support.
        let schema = Schema([StoredPerson.self, StoredGift.self])
        let configuration = ModelConfiguration(
            "WhoGaveWhatSwiftData", schema: schema, url: output, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var people: [String: StoredPerson] = [:]
        for person in manifest.dataset.people {
            #if HAS_ROLE
                let stored = StoredPerson(
                    id: person.id, name: person.name, colorHex: person.colorHex,
                    roleRawValue: person.role ?? "contact", sortIndex: person.sortIndex)
            #else
                let stored = StoredPerson(
                    id: person.id, name: person.name, colorHex: person.colorHex, sortIndex: person.sortIndex)
            #endif
            #if HAS_IMAGE_DATA
                stored.imageData = person.imageBase64.flatMap { Data(base64Encoded: $0) }
            #endif
            context.insert(stored)
            people[person.id] = stored
        }

        for gift in manifest.dataset.gifts {
            guard let giver = people[gift.giverID] else { throw FixtureWriterError.unknownPerson(gift.giverID) }
            guard let recipient = people[gift.recipientID] else {
                throw FixtureWriterError.unknownPerson(gift.recipientID)
            }
            // Since per-gift currencies the initializer takes the currency; earlier ones had no such attribute.
            #if HAS_CURRENCY_CODE
                let stored = StoredGift(
                    id: gift.id, emoji: gift.emoji, name: gift.name, giver: giver, recipient: recipient,
                    paidByYou: gift.paidByYou, occasion: gift.occasion, date: gift.date, value: gift.value,
                    createdAt: gift.createdAt, currencyCode: gift.currencyCode)
            #else
                let stored = StoredGift(
                    id: gift.id, emoji: gift.emoji, name: gift.name, giver: giver, recipient: recipient,
                    paidByYou: gift.paidByYou, occasion: gift.occasion, date: gift.date, value: gift.value,
                    createdAt: gift.createdAt)
            #endif
            #if HAS_EMOJI_PICKED_BY_USER
                stored.emojiPickedByUser = gift.emojiPickedByUser ?? false
            #endif
            #if HAS_LAST_SAVED_AT
                stored.lastSavedAt = gift.lastSavedAt
            #endif
            context.insert(stored)
        }

        try context.save()
        print("Wrote \(people.count) people and \(manifest.dataset.gifts.count) gifts to \(output.path)")
    }
}
