import Foundation
import SwiftData
import Testing

@testable import WhoGaveWhat

/// The store files earlier builds wrote, described by `Fixtures/StoreFixtures/store-fixtures.json` and
/// written by `scripts/store-fixtures/generate.py` with each build's own model code.
enum StoreFixtures {
    struct Fixture: Decodable, CustomTestStringConvertible {
        let file: String
        let commit: String
        let builds: String
        /// The optional attributes this schema version had, as named in the manifest.
        let features: Set<String>

        var testDescription: String { "\(file) (\(builds))" }
    }

    struct Dataset: Decodable {
        struct Person: Decodable {
            let id: String
            let name: String
            let colorHex: Int64
            let sortIndex: Int
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
            let currencyCode: String
        }

        let people: [Person]
        let gifts: [Gift]
    }

    struct Manifest: Decodable {
        let fixtures: [Fixture]
        let dataset: Dataset
    }

    private final class BundleToken {}

    static let manifest: Manifest = {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Manifest.self, from: Data(contentsOf: resource("store-fixtures.json")))
        } catch {
            fatalError("The store fixture manifest does not load: \(error)")
        }
    }()

    static var newest: Fixture {
        guard let fixture = manifest.fixtures.last else { fatalError("The store fixture manifest lists no fixtures") }
        return fixture
    }

    static func url(of fixture: Fixture) throws -> URL {
        try resource(fixture.file)
    }

    /// Xcode copies the fixtures flat into the test bundle; a folder copy keeps their subdirectory.
    private static func resource(_ name: String) throws -> URL {
        let bundle = Bundle(for: BundleToken.self)
        let file = name as NSString
        for subdirectory in [nil, "Fixtures/StoreFixtures"] {
            if let url = bundle.url(
                forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: subdirectory)
            {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
    }

    /// The people that schema version could hold, in their stored order.
    static func expectedPeople(for fixture: Fixture) -> [Person] {
        manifest.dataset.people.sorted { $0.sortIndex < $1.sortIndex }.map { person in
            Person(
                id: person.id, name: person.name, colorHex: UInt(person.colorHex),
                imageData: fixture.features.contains("imageData")
                    ? person.imageBase64.flatMap { Data(base64Encoded: $0) } : nil)
        }
    }

    /// The currency the migration tests open stores with. The dataset has rubles too, so a gift that keeps
    /// rubles proves it kept its own currency and one that turns into dollars proves it took this one.
    static let migrationCurrency = SupportedCurrency.usd

    /// The gifts that schema version could hold; attributes it lacked take their migration defaults, and
    /// gifts from before per-gift currencies take `legacyCurrency`.
    static func expectedGifts(
        for fixture: Fixture, legacyCurrency: SupportedCurrency = migrationCurrency
    ) -> [WhoGaveWhat.Gift] {
        manifest.dataset.gifts.map { gift in
            let currency =
                fixture.features.contains("currencyCode")
                ? SupportedCurrency(rawValue: gift.currencyCode) ?? legacyCurrency : legacyCurrency
            return WhoGaveWhat.Gift(
                id: gift.id, emoji: gift.emoji, name: gift.name, giverID: gift.giverID,
                recipientID: gift.recipientID, paidByYou: gift.paidByYou, occasion: gift.occasion, date: gift.date,
                value: gift.value, currency: currency, createdAt: gift.createdAt,
                emojiPickedByUser: fixture.features.contains("emojiPickedByUser")
                    ? (gift.emojiPickedByUser ?? false) : false,
                lastSavedAt: fixture.features.contains("lastSavedAt") ? gift.lastSavedAt : nil)
        }
        .sorted { $0.id < $1.id }
    }
}

@MainActor
struct StoreFixtureMigrationTests {
    /// Copies the fixture into a fresh folder, because opening a store migrates it in place.
    private func copy(_ fixture: StoreFixtures.Fixture) throws -> (directory: URL, store: URL) {
        let directory = try makeTemporaryDirectory()
        let store = directory.appending(path: "\(SwiftDataStore.storeName).store")
        try FileManager.default.copyItem(at: try StoreFixtures.url(of: fixture), to: store)
        return (directory, store)
    }

    @Test(arguments: StoreFixtures.manifest.fixtures)
    func storeFromAnEarlierBuildOpensWithoutDataLoss(_ fixture: StoreFixtures.Fixture) throws {
        let (directory, url) = try copy(fixture)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let store = try SwiftDataStore(url: url, legacyGiftCurrency: StoreFixtures.migrationCurrency)
            #expect(store.legacyGiftCurrencyError == nil)
            let gifts = try SwiftDataGiftGateway(context: store.context).loadGifts().sorted { $0.id < $1.id }
            let people = try SwiftDataPeopleGateway(context: store.context).loadPeople().people

            #expect(people == StoreFixtures.expectedPeople(for: fixture))
            #expect(gifts == StoreFixtures.expectedGifts(for: fixture))

            // The migrated store takes new records and keeps the relationships of the old ones.
            let added = WhoGaveWhat.Gift(
                id: "g-after-migration", emoji: "🎂", name: "Cake", giverID: "p-mark", recipientID: "p-anna",
                paidByYou: true, occasion: "Birthday", date: Date(timeIntervalSince1970: 1_790_000_000), value: 25,
                currency: .rub, createdAt: Date(timeIntervalSince1970: 1_790_000_000), lastSavedAt: Date(timeIntervalSince1970: 1_790_000_100))
            try SwiftDataGiftGateway(context: store.context).save(added)
            let stored = try store.context.fetch(FetchDescriptor<StoredPerson>())
            #expect(stored.first { $0.id == "p-anna" }?.giftsReceived.count == 3)
        }

        // Reopening the migrated file finds the old records and the new one, and the migration currency is
        // stored: another one now changes nothing.
        let reopened = try SwiftDataStore(url: url, legacyGiftCurrency: .rub)
        #expect(try reopened.assignLegacyGiftCurrency(.rub) == 0)
        let gifts = try SwiftDataGiftGateway(context: reopened.context).loadGifts()
        #expect(gifts.count == StoreFixtures.manifest.dataset.gifts.count + 1)
        #expect(gifts.first { $0.id == "g-after-migration" }?.lastSavedAt == Date(timeIntervalSince1970: 1_790_000_100))
        #expect(gifts.first { $0.id == "g-after-migration" }?.currency == .rub)
        #expect(
            gifts.filter { $0.id != "g-after-migration" }.sorted { $0.id < $1.id }
                == StoreFixtures.expectedGifts(for: fixture))
    }

    /// A schema change needs a fixture written by the build that ships it, so the next change is tested
    /// against it. The newest fixture must therefore have every optional attribute the current models have.
    @Test func newestFixtureCoversTheCurrentSchema() {
        let required: Set<String> = [
            "id", "name", "colorHex", "sortIndex", "giftsGiven", "giftsReceived", "emoji", "giver", "recipient",
            "paidByYou", "occasion", "date", "value", "createdAt"
        ]
        let current = Set(
            SwiftDataStore.schema.entities.flatMap { $0.attributes.map(\.name) + $0.relationships.map(\.name) })
        #expect(required.isSubset(of: current))
        #expect(current.subtracting(required) == StoreFixtures.newest.features.subtracting(["role"]))
    }

    @Test func fixturesAreDistinctSchemaVersions() throws {
        let fixtures = StoreFixtures.manifest.fixtures
        #expect(fixtures.count >= 4)
        #expect(Set(fixtures.map(\.features)).count == fixtures.count)
        for fixture in fixtures {
            #expect(FileManager.default.fileExists(atPath: try StoreFixtures.url(of: fixture).path))
        }
    }
}
