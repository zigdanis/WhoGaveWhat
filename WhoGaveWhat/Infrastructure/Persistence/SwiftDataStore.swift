import Foundation
import SwiftData
import UIKit

@MainActor
final class SwiftDataStore {
    /// A new, explicit namespace for this app's SwiftData schema.
    static let storeName = "WhoGaveWhatSwiftData"

    /// The seeded person who represents the user's own viewpoint.
    static let seedSelfPersonID = "anton"

    static let shared: SwiftDataStore = {
        do {
            return try SwiftDataStore()
        } catch {
            fatalError("SwiftData store failed to load: \(error)")
        }
    }()

    /// Sample amounts follow the currency the app resolves for this device, as the screenshots show them.
    static let preview: SwiftDataStore = {
        do {
            let currency = SupportedCurrency(rawValue: UserDefaultsPreferencesGateway().currencyCode) ?? .usd
            return try SwiftDataStore(inMemory: true, seed: true, sampleCurrency: currency)
        } catch {
            fatalError("SwiftData preview store failed to load: \(error)")
        }
    }()

    let container: ModelContainer
    let context: ModelContext

    init(
        inMemory: Bool = false,
        seed: Bool = false,
        sampleCurrency: SupportedCurrency = .rub
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

        if seed {
            try seedIfNeeded(currency: sampleCurrency)
        }
    }

    private func seedIfNeeded(currency: SupportedCurrency) throws {
        guard try context.fetchCount(FetchDescriptor<StoredPerson>()) == 0 else { return }

        func localized(_ value: String) -> String {
            String(localized: String.LocalizationValue(value))
        }

        let people: [(String, String, Int64)] = [
            ("anton", "Anton", 0x12161C),
            ("marina", "Marina", 0x12805C),
            ("sofia", "Sofia", 0x5B6573),
            ("alisa", "Alisa", 0x2F6FAE),
            ("maria", "Aunt Maria", 0x12161C),
            ("pavel", "Grandpa Pavel", 0x12805C),
            ("igor", "Igor", 0x2F6FAE),
            ("olga", "Olga", 0x5B6573),
            ("lena", "Lena", 0x7A5CCB),
            ("dmitri", "Dmitri", 0x0E7C8C)
        ]

        var peopleByID: [String: StoredPerson] = [:]
        for (index, person) in people.enumerated() {
            let storedPerson = StoredPerson(
                id: person.0,
                name: localized(person.1),
                colorHex: person.2,
                sortIndex: index,
                imageData: Self.samplePhoto(for: person.0)
            )
            context.insert(storedPerson)
            peopleByID[person.0] = storedPerson
        }

        // id, emoji, name, giver, recipient, paid, occasion, date, value in rubles, value in dollars
        let gifts: [(String, String, String, String, String, Bool, String, String, Double, Double)] = [
            ("g1", "💐", "Bouquet of roses", "maria", "marina", false, "Birthday", "2026-05-12", 2000, 45),
            ("g2", "⌚", "Wristwatch", "pavel", "anton", false, "Birthday", "2026-04-03", 9500, 180),
            ("g3", "🧸", "Teddy bear", "maria", "alisa", false, "New Year", "2026-01-02", 1500, 25),
            ("g4", "📚", "Book set", "igor", "anton", false, "Graduation", "2026-03-20", 1800, 40),
            ("g5", "🍷", "Bottle of wine", "dmitri", "anton", false, "Housewarming", "2026-02-15", 1900, 30),
            ("g6", "🪴", "Potted plant", "olga", "marina", false, "Just because", "2026-05-28", 1200, 25),
            ("g7", "🪆", "Matryoshka doll", "pavel", "sofia", false, "New Year", "2026-01-02", 1400, 30),
            ("g8", "🧱", "Lego set", "sofia", "lena", true, "Birthday", "2026-06-02", 1500, 60),
            ("g9", "💍", "Silver necklace", "marina", "maria", true, "Anniversary", "2026-02-14", 4500, 120),
            ("g10", "🍫", "Box of chocolates", "anton", "olga", true, "Just because", "2026-05-28", 700, 15),
            ("g11", "🍷", "Bottle of wine", "anton", "igor", true, "Birthday", "2026-04-18", 2100, 35),
            ("g12", "🎟️", "Concert tickets", "anton", "dmitri", true, "Birthday", "2026-03-09", 3000, 90)
        ]
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"

        for (index, gift) in gifts.enumerated() {
            guard let giver = peopleByID[gift.3],
                let recipient = peopleByID[gift.4],
                let date = formatter.date(from: gift.7)
            else { continue }
            context.insert(
                StoredGift(
                    id: gift.0,
                    emoji: gift.1,
                    name: localized(gift.2),
                    giver: giver,
                    recipient: recipient,
                    paidByYou: gift.5,
                    occasion: gift.6,
                    date: date,
                    value: currency == .usd ? gift.9 : gift.8,
                    createdAt: date.addingTimeInterval(TimeInterval(index))
                ))
        }

        try context.save()
    }

    /// Generated portraits for the sample people, from `SampleContent`. Xcode leaves that folder
    /// out of archives (`DEVELOPMENT_ASSET_PATHS`), so release builds get no photo here.
    static func samplePhoto(for personID: String) -> Data? {
        NSDataAsset(name: "sample-face-\(personID)")?.data
    }
}
