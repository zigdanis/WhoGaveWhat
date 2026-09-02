import Foundation
import SwiftData

@MainActor
final class SwiftDataStore {
    /// A new, explicit namespace for this app's SwiftData schema.
    static let storeName = "WhoGaveWhatSwiftData"

    static let shared: SwiftDataStore = {
        do {
            return try SwiftDataStore()
        } catch {
            fatalError("SwiftData store failed to load: \(error)")
        }
    }()

    static let preview: SwiftDataStore = {
        do {
            return try SwiftDataStore(inMemory: true, seed: true)
        } catch {
            fatalError("SwiftData preview store failed to load: \(error)")
        }
    }()

    let container: ModelContainer
    let context: ModelContext

    init(
        inMemory: Bool = false,
        seed: Bool = false,
        bootstrapsSelf: Bool? = nil
    ) throws {
        let schema = Schema([StoredPerson.self, StoredGift.self])
        let configuration = ModelConfiguration(
            Self.storeName,
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false

        let shouldBootstrapSelf = bootstrapsSelf ?? !inMemory
        if seed {
            try seedIfNeeded()
        } else if shouldBootstrapSelf {
            try ensureSelf()
        }
    }

    private func ensureSelf() throws {
        guard try context.fetchCount(FetchDescriptor<StoredPerson>()) == 0 else { return }
        context.insert(StoredPerson(
            id: "you",
            name: String(localized: "You"),
            colorHex: 0x12161C,
            roleRawValue: PersonRole.household.rawValue,
            sortIndex: 0
        ))
        try context.save()
    }

    private func seedIfNeeded() throws {
        guard try context.fetchCount(FetchDescriptor<StoredPerson>()) == 0 else { return }

        func localized(_ value: String) -> String {
            String(localized: String.LocalizationValue(value))
        }

        let household: [(String, String, Int64)] = [
            ("you", "You", 0x12161C),
            ("marina", "Marina", 0x12805C),
            ("sofia", "Sofia", 0x5B6573),
            ("alisa", "Alisa", 0x2F6FAE),
        ]
        let contacts: [(String, String, Int64)] = [
            ("maria", "Aunt Maria", 0x12161C),
            ("pavel", "Grandpa Pavel", 0x12805C),
            ("igor", "Igor", 0x2F6FAE),
            ("olga", "Olga", 0x5B6573),
            ("lena", "Lena", 0x7A5CCB),
            ("dmitri", "Dmitri", 0x0E7C8C),
        ]

        var peopleByID: [String: StoredPerson] = [:]
        for (index, person) in household.enumerated() {
            let storedPerson = StoredPerson(
                id: person.0,
                name: localized(person.1),
                colorHex: person.2,
                roleRawValue: PersonRole.household.rawValue,
                sortIndex: index
            )
            context.insert(storedPerson)
            peopleByID[person.0] = storedPerson
        }
        for (index, person) in contacts.enumerated() {
            let storedPerson = StoredPerson(
                id: person.0,
                name: localized(person.1),
                colorHex: person.2,
                roleRawValue: PersonRole.contact.rawValue,
                sortIndex: index
            )
            context.insert(storedPerson)
            peopleByID[person.0] = storedPerson
        }

        // id, emoji, name, giver, recipient, paid, occasion, date, value
        let gifts: [(String, String, String, String, String, Bool, String, String, Double)] = [
            ("g1", "💐", "Bouquet of roses", "maria", "marina", false, "Birthday", "2026-05-12", 2000),
            ("g2", "⌚", "Wristwatch", "pavel", "you", false, "Birthday", "2026-04-03", 9500),
            ("g3", "🧸", "Teddy bear", "maria", "alisa", false, "New Year", "2026-01-02", 1500),
            ("g4", "📚", "Book set", "igor", "you", false, "Graduation", "2026-03-20", 1800),
            ("g5", "🍷", "Bottle of wine", "dmitri", "you", false, "Housewarming", "2026-02-15", 1900),
            ("g6", "🪴", "Potted plant", "olga", "marina", false, "Just because", "2026-05-28", 1200),
            ("g7", "🪆", "Matryoshka doll", "pavel", "sofia", false, "New Year", "2026-01-02", 1400),
            ("g8", "🧱", "Lego set", "sofia", "lena", true, "Birthday", "2026-06-02", 1500),
            ("g9", "💍", "Silver necklace", "marina", "maria", true, "Anniversary", "2026-02-14", 4500),
            ("g10", "🍫", "Box of chocolates", "you", "olga", true, "Just because", "2026-05-28", 700),
            ("g11", "🍷", "Bottle of wine", "you", "igor", true, "Birthday", "2026-04-18", 2100),
            ("g12", "🎟️", "Concert tickets", "you", "dmitri", true, "Birthday", "2026-03-09", 3000),
        ]
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"

        for (index, gift) in gifts.enumerated() {
            guard let giver = peopleByID[gift.3],
                  let recipient = peopleByID[gift.4],
                  let date = formatter.date(from: gift.7) else { continue }
            context.insert(StoredGift(
                id: gift.0,
                emoji: gift.1,
                name: localized(gift.2),
                giver: giver,
                recipient: recipient,
                paidByYou: gift.5,
                occasion: gift.6,
                date: date,
                value: gift.8,
                createdAt: date.addingTimeInterval(TimeInterval(index))
            ))
        }

        try context.save()
    }
}
