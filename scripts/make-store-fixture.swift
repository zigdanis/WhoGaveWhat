// Writes WhoGaveWhatTests/Fixtures/WhoGaveWhat-1.2.0.store, the store `LegacyStoreMigrationTests`
// migrates. It compiles the 1.2.0 model file as it shipped, so the store has that schema exactly:
//
//   git show d7f0af8:WhoGaveWhat/Infrastructure/Persistence/SwiftDataModels.swift > /tmp/Models120.swift
//   xcrun swiftc -parse-as-library /tmp/Models120.swift scripts/make-store-fixture.swift -o /tmp/make-fixture
//   /tmp/make-fixture "$PWD/WhoGaveWhatTests/Fixtures/WhoGaveWhat-1.2.0.store"
//   sqlite3 WhoGaveWhatTests/Fixtures/WhoGaveWhat-1.2.0.store \
//     "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;"
//
// The last step folds the write-ahead log into the one file that is committed.
import Foundation
import SwiftData

@main
struct MakeFixture {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let schema = Schema([StoredPerson.self, StoredGift.self])
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let anna = StoredPerson(id: "anna", name: "Anna", colorHex: 0x12805C, sortIndex: 0)
        let boris = StoredPerson(id: "boris", name: "Boris", colorHex: 0x2F6FAE, sortIndex: 1)
        let vera = StoredPerson(id: "vera", name: "Vera", colorHex: 0x5B6573, sortIndex: 2)
        [anna, boris, vera].forEach(context.insert)
        func day(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
        context.insert(StoredGift(
            id: "fixture-watch", emoji: "⌚", name: "Wristwatch", giver: boris, recipient: anna,
            paidByYou: false, occasion: "Birthday", date: day(1_767_225_600), value: 100,
            createdAt: day(1_767_229_200), emojiPickedByUser: true, lastSavedAt: day(1_767_232_800)))
        context.insert(StoredGift(
            id: "fixture-book", emoji: "📚", name: "Book set", giver: anna, recipient: vera,
            paidByYou: true, occasion: "Graduation", date: day(1_772_323_200), value: 2_500,
            createdAt: day(1_772_326_800)))
        context.insert(StoredGift(
            id: "fixture-zero", emoji: "🎁", name: "Hand-made card", giver: vera, recipient: boris,
            paidByYou: false, occasion: "Just because", date: day(1_777_593_600), value: 0,
            createdAt: day(1_777_597_200), lastSavedAt: day(1_777_600_800)))
        try context.save()
    }
}
