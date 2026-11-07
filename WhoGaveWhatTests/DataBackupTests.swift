import Foundation
import SwiftData
import Testing

@testable import WhoGaveWhat

// MARK: - Fixtures

private enum BackupSamples {
    static let photo = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])
    static let otherPhoto = Data([0xFF, 0xD8, 0xFF, 0x09])

    static func backup(
        createdAt: Date = Date(timeIntervalSince1970: 1_790_000_000),
        people: [DataBackup.Person] = [
            person("p-anna", "Anna", sortIndex: 0, photo: photo),
            person("p-maria", "Aunt Vera", sortIndex: 1)
        ],
        gifts: [DataBackup.Gift] = [gift("g-1", from: "p-maria", to: "p-anna")],
        defaultCurrency: SupportedCurrency? = .rub,
        selfPersonID: String? = "p-anna"
    ) -> DataBackup {
        DataBackup(
            createdAt: createdAt, appVersion: "1.3.0 (30)", deviceModel: "iPhone", defaultCurrency: defaultCurrency,
            selfPersonID: selfPersonID, people: people, gifts: gifts)
    }

    static func person(_ id: String, _ name: String, sortIndex: Int, photo: Data? = nil) -> DataBackup.Person {
        DataBackup.Person(id: id, name: name, colorHex: 0x12805C, sortIndex: sortIndex, photo: photo)
    }

    static func gift(
        _ id: String, from giver: String, to recipient: String, currency: SupportedCurrency = .rub
    ) -> DataBackup.Gift {
        DataBackup.Gift(
            id: id, emoji: "🎁", name: "Gift \(id)", giverID: giver, recipientID: recipient, paidByYou: true,
            occasion: "Birthday", date: Date(timeIntervalSince1970: 1_780_000_000), value: 1_500, currency: currency,
            createdAt: Date(timeIntervalSince1970: 1_780_000_123), emojiPickedByUser: true,
            lastSavedAt: Date(timeIntervalSince1970: 1_780_000_456))
    }

    private final class BundleToken {}

    static func goldenV1() throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        for subdirectory in [nil, "Fixtures/Backups"] {
            if let url = bundle.url(forResource: "backup-v1", withExtension: "json", subdirectory: subdirectory) {
                return try Data(contentsOf: url)
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

private func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

// MARK: - Codec

struct DataBackupCodecTests {
    @Test func inlineFileRoundTripsEveryField() throws {
        let backup = BackupSamples.backup()
        let encoded = try DataBackupCodec.encode(backup, photos: .inline)
        #expect(encoded.photos.isEmpty)
        #expect(try DataBackupCodec.decode(encoded.json) == backup)
    }

    @Test func externalPhotosAreSeparateFilesNamedByContent() throws {
        let backup = BackupSamples.backup()
        let encoded = try DataBackupCodec.encode(backup, photos: .external)
        let name = DataBackupCodec.photoFileName(for: BackupSamples.photo)
        #expect(encoded.photos == [name: BackupSamples.photo])
        #expect(DataBackupCodec.isSafePhotoFileName(name))
        #expect(DataBackupCodec.referencedPhotoFiles(in: encoded.json) == [name])
        #expect(try DataBackupCodec.decode(encoded.json) { encoded.photos[$0] } == backup)
    }

    @Test func aMissingPhotoFileRestoresAsNoPhoto() throws {
        let encoded = try DataBackupCodec.encode(BackupSamples.backup(), photos: .external)
        let decoded = try DataBackupCodec.decode(encoded.json) { _ in nil }
        #expect(decoded.people.first?.photo == nil)
        #expect(decoded.gifts.count == 1)
    }

    @Test func readsTheCommittedVersionOneFile() throws {
        let backup = try DataBackupCodec.decode(try BackupSamples.goldenV1())
        #expect(backup.deviceModel == "iPhone")
        #expect(backup.defaultCurrency == .rub)
        #expect(backup.selfPersonID == "p-anna")
        #expect(backup.people.map(\.id) == ["p-anna", "p-maria"])
        #expect(backup.people[0].photo == Data([1, 2, 3]))
        #expect(backup.people[1].photo == nil)
        #expect(backup.people[1].colorHex == 8_018_123)
        let roses = try #require(backup.gifts.first { $0.id == "g-roses" })
        #expect(roses.currency == .rub)
        #expect(roses.emojiPickedByUser)
        #expect(roses.createdAt == Date(timeIntervalSince1970: 1_778_577_330.25))
        let books = try #require(backup.gifts.first { $0.id == "g-books" })
        // Dates without milliseconds and a missing optional flag still read.
        #expect(books.currency == .usd)
        #expect(books.value == 40.5)
        #expect(!books.emojiPickedByUser)
        #expect(books.lastSavedAt == nil)
    }

    @Test func refusesFilesThatAreNotBackups() throws {
        #expect(throws: DataBackupError.unreadable) { try DataBackupCodec.decode(Data("not json".utf8)) }
        #expect(throws: DataBackupError.unreadable) {
            try DataBackupCodec.decode(try json(["format": "something-else", "version": 1]))
        }
        #expect(throws: DataBackupError.unreadable) {
            try DataBackupCodec.decode(try json(["format": DataBackupCodec.format, "version": 1, "people": []]))
        }
    }

    @Test func refusesANewerFormatWithItsOwnError() throws {
        let data = try json(["format": DataBackupCodec.format, "version": 2, "something": "new"])
        #expect(throws: DataBackupError.newerVersion(2)) { try DataBackupCodec.decode(data) }
    }

    @Test func refusesContradictoryRecords() throws {
        func decoding(_ backup: DataBackup) throws -> DataBackup {
            try DataBackupCodec.decode(try DataBackupCodec.encode(backup, photos: .inline).json)
        }
        let anna = BackupSamples.person("p-anna", "Anna", sortIndex: 0)
        let maria = BackupSamples.person("p-maria", "Maria", sortIndex: 1)
        #expect(throws: DataBackupError.inconsistent("duplicate_person")) {
            try decoding(BackupSamples.backup(people: [anna, anna], gifts: []))
        }
        #expect(throws: DataBackupError.inconsistent("missing_person")) {
            try decoding(BackupSamples.backup(people: [anna], gifts: [BackupSamples.gift("g", from: "p-x", to: "p-anna")]))
        }
        #expect(throws: DataBackupError.inconsistent("same_person")) {
            try decoding(BackupSamples.backup(people: [anna], gifts: [BackupSamples.gift("g", from: "p-anna", to: "p-anna")]))
        }
        let gift = BackupSamples.gift("g", from: "p-anna", to: "p-maria")
        #expect(throws: DataBackupError.inconsistent("duplicate_gift")) {
            try decoding(BackupSamples.backup(people: [anna, maria], gifts: [gift, gift]))
        }
    }

    @Test func refusesAnUnknownCurrency() throws {
        var object = try #require(
            JSONSerialization.jsonObject(with: try BackupSamples.goldenV1()) as? [String: Any])
        var gifts = try #require(object["gifts"] as? [[String: Any]])
        gifts[0]["currency"] = "EUR"
        object["gifts"] = gifts
        #expect(throws: DataBackupError.inconsistent("unknown_currency")) { try DataBackupCodec.decode(try json(object)) }
    }

    @Test func refusesAmountsNoGiftCanHave() throws {
        var gift = BackupSamples.gift("g-1", from: "p-maria", to: "p-anna")
        gift = DataBackup.Gift(
            id: gift.id, emoji: gift.emoji, name: gift.name, giverID: gift.giverID, recipientID: gift.recipientID,
            paidByYou: gift.paidByYou, occasion: gift.occasion, date: gift.date, value: 1e100, currency: gift.currency,
            createdAt: gift.createdAt, emojiPickedByUser: gift.emojiPickedByUser, lastSavedAt: gift.lastSavedAt)
        #expect(throws: DataBackupError.inconsistent("value_out_of_range")) {
            try BackupSamples.backup(gifts: [gift]).validated()
        }
    }

    @Test func aViewpointWithoutItsPersonIsDropped() throws {
        let backup = BackupSamples.backup(selfPersonID: "p-gone")
        let decoded = try DataBackupCodec.decode(try DataBackupCodec.encode(backup, photos: .inline).json)
        #expect(decoded.selfPersonID == nil)
    }

    @Test func photoReferencesCannotLeaveTheBackupFolder() {
        #expect(!DataBackupCodec.isSafePhotoFileName("../../etc/passwd"))
        #expect(!DataBackupCodec.isSafePhotoFileName("abc.photo"))
        #expect(DataBackupCodec.isSafePhotoFileName(String(repeating: "a", count: 64) + ".photo"))
    }

    @Test func exportFileNamesSortByTime() {
        let name = AppComposition.exportFileName(for: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(name.hasPrefix("WhoGaveWhat-2026-"))
        #expect(name.hasSuffix(".whogavewhat"))
    }
}

// MARK: - SwiftData archive

@MainActor
struct JournalArchiveGatewayTests {
    @Test func archiveHoldsEveryStoredFieldInPeopleOrder() throws {
        let store = try SwiftDataStore(inMemory: true, seed: true)
        let archive = try SwiftDataJournalArchiveGateway(context: store.context).loadArchive()
        let people = try SwiftDataPeopleGateway(context: store.context).loadPeople().people
        let gifts = try SwiftDataGiftGateway(context: store.context).loadGifts()

        #expect(archive.people.map(\.id) == people.map(\.id))
        #expect(archive.people.map(\.sortIndex) == Array(0..<people.count))
        #expect(archive.people.map(\.colorHex) == people.map(\.colorHex))
        #expect(archive.people.map(\.photo) == people.map(\.imageData))
        #expect(archive.gifts.count == gifts.count)
        for gift in gifts {
            let archived = try #require(archive.gifts.first { $0.id == gift.id })
            #expect(archived.currency == gift.currency)
            #expect(archived.giverID == gift.giverID)
            #expect(archived.recipientID == gift.recipientID)
            #expect(archived.date == gift.date)
            #expect(archived.createdAt == gift.createdAt)
        }
    }

    @Test func restoreIntoAnEmptyStoreRebuildsTheJournalExactly() throws {
        let source = try SwiftDataStore(inMemory: true, seed: true)
        let original = try SwiftDataJournalArchiveGateway(context: source.context).loadArchive()
        let backup = BackupSamples.backup(people: original.people, gifts: original.gifts, selfPersonID: "anton")

        let target = try SwiftDataStore(inMemory: true)
        let gateway = SwiftDataJournalArchiveGateway(context: target.context)
        let summary = try gateway.restore(backup)

        #expect(summary.restoredIntoEmptyJournal)
        #expect(summary.peopleAdded == original.people.count)
        #expect(summary.giftsAdded == original.gifts.count)
        let restored = try gateway.loadArchive()
        #expect(restored.people == original.people)
        #expect(restored.gifts.sorted { $0.id < $1.id } == original.gifts.sorted { $0.id < $1.id })
    }

    @Test func restoreNextToExistingRecordsOnlyAddsWhatIsMissing() throws {
        let store = try SwiftDataStore(inMemory: true)
        let people = SwiftDataPeopleGateway(context: store.context)
        try people.createPerson(id: "p-local-anna", name: "anna ", colorHex: 0x123456, sortIndex: 5)
        try people.createPerson(id: "p-maria", name: "Maria (renamed here)", colorHex: 0x654321, sortIndex: 6)
        try SwiftDataGiftGateway(context: store.context).save(
            Gift(
                id: "g-1", emoji: "🎂", name: "Local copy", giverID: "p-maria", recipientID: "p-local-anna",
                paidByYou: false, occasion: "", date: .now, value: 5, currency: .usd, createdAt: .now))

        let backup = BackupSamples.backup(
            people: [
                BackupSamples.person("p-anna", "Anna", sortIndex: 0),
                BackupSamples.person("p-maria", "Aunt Vera", sortIndex: 1),
                BackupSamples.person("p-ivan", "Ivan", sortIndex: 2)
            ],
            gifts: [
                BackupSamples.gift("g-1", from: "p-maria", to: "p-anna"),
                BackupSamples.gift("g-2", from: "p-ivan", to: "p-anna"),
                BackupSamples.gift("g-3", from: "p-anna", to: "p-maria", currency: .usd)
            ])
        let gateway = SwiftDataJournalArchiveGateway(context: store.context)
        let summary = try gateway.restore(backup)

        #expect(!summary.restoredIntoEmptyJournal)
        #expect(summary.peopleMatched == 2)
        #expect(summary.peopleAdded == 1)
        #expect(summary.giftsAdded == 2)
        #expect(summary.giftsAlreadyHere == 1)

        let archive = try gateway.loadArchive()
        // The local records win: names, colors and the existing gift stay as they were.
        #expect(archive.people.first { $0.id == "p-maria" }?.name == "Maria (renamed here)")
        #expect(archive.gifts.first { $0.id == "g-1" }?.name == "Local copy")
        // The backup's Anna is the local "anna"; the new person goes after the local ones.
        #expect(archive.gifts.first { $0.id == "g-2" }?.recipientID == "p-local-anna")
        #expect(archive.gifts.first { $0.id == "g-3" }?.giverID == "p-local-anna")
        #expect(archive.gifts.first { $0.id == "g-3" }?.currency == .usd)
        #expect(archive.people.map(\.id) == ["p-local-anna", "p-maria", "p-ivan"])
        #expect(archive.people.last?.sortIndex == 7)
    }

    @Test func restoringTheSameBackupTwiceAddsNothingTheSecondTime() throws {
        let store = try SwiftDataStore(inMemory: true)
        let gateway = SwiftDataJournalArchiveGateway(context: store.context)
        try gateway.restore(BackupSamples.backup())
        let second = try gateway.restore(BackupSamples.backup())
        #expect(!second.addedAnything)
        #expect(second.peopleMatched == 2)
        #expect(second.giftsAlreadyHere == 1)
    }

    @Test func aGiftBetweenTwoBackupPeopleWhoAreOnePersonHereIsSkipped() throws {
        let store = try SwiftDataStore(inMemory: true)
        try SwiftDataPeopleGateway(context: store.context).createPerson(
            id: "p-anna", name: "Anna", colorHex: 0, sortIndex: 0)
        let backup = BackupSamples.backup(
            people: [BackupSamples.person("p-anna", "Anna", sortIndex: 0), BackupSamples.person("p-2", "ANNA", sortIndex: 1)],
            gifts: [BackupSamples.gift("g", from: "p-anna", to: "p-2")])
        let summary = try SwiftDataJournalArchiveGateway(context: store.context).restore(backup)
        #expect(summary.giftsAdded == 0)
        #expect(summary.giftsWithoutPlace == 1)
        #expect(RestoreMessages.outcome(summary).contains("1"))
    }

    @Test func restoredPeopleAreRenumberedInBackupOrder() throws {
        let store = try SwiftDataStore(inMemory: true)
        let gateway = SwiftDataJournalArchiveGateway(context: store.context)
        try gateway.restore(
            BackupSamples.backup(
                people: [
                    BackupSamples.person("p-last", "Last", sortIndex: Int.max),
                    BackupSamples.person("p-first", "First", sortIndex: -40)
                ],
                gifts: []))
        let archive = try gateway.loadArchive()
        #expect(archive.people.map(\.id) == ["p-first", "p-last"])
        #expect(archive.people.map(\.sortIndex) == [0, 1])
        // A later restore appends after them without overflowing.
        try gateway.restore(BackupSamples.backup(people: [BackupSamples.person("p-new", "New", sortIndex: 0)], gifts: []))
        #expect(try gateway.loadArchive().people.last?.sortIndex == 2)
    }

    @Test func aFailedSaveAddsNothing() throws {
        struct SaveFailed: Error {}
        let store = try SwiftDataStore(inMemory: true)
        let failing = SwiftDataJournalArchiveGateway(context: store.context, save: { _ in throw SaveFailed() })
        #expect(throws: SaveFailed.self) { try failing.restore(BackupSamples.backup()) }
        let archive = try SwiftDataJournalArchiveGateway(context: store.context).loadArchive()
        #expect(archive.people.isEmpty)
        #expect(archive.gifts.isEmpty)
    }

    @Test func giftsFromBeforePerGiftCurrenciesTakeTheLegacyCurrency() throws {
        let store = try SwiftDataStore(inMemory: true)
        try SwiftDataJournalArchiveGateway(context: store.context).restore(BackupSamples.backup())
        let stored = try #require(try store.context.fetch(FetchDescriptor<StoredGift>()).first)
        stored.currencyCode = nil
        try store.context.save()

        let archive = try SwiftDataJournalArchiveGateway(context: store.context, legacyGiftCurrency: .usd).loadArchive()
        #expect(archive.gifts.first?.currency == .usd)
        #expect(throws: SwiftDataPersistenceError.self) {
            try SwiftDataJournalArchiveGateway(context: store.context).loadArchive()
        }
    }
}

// MARK: - Backup folder

struct BackupFolderStoreTests {
    private let writer = UUID().uuidString

    private func makeStore() throws -> BackupFolderStore {
        BackupFolderStore(root: try makeTemporaryDirectory(), usesFileCoordination: false)
    }

    private func photoFiles(_ store: BackupFolderStore, writer: String) -> Set<String> {
        let folder = store.root.appending(path: writer).appending(path: BackupFolderStore.photosFolderName)
        return Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path())) ?? [])
    }

    @Test func writesAndReadsBackOneInstallsBackup() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        #expect(!store.hasBackup(writerID: writer))

        let backup = BackupSamples.backup()
        try store.write(backup, writerID: writer)

        #expect(store.hasBackup(writerID: writer))
        #expect(photoFiles(store, writer: writer) == [DataBackupCodec.photoFileName(for: BackupSamples.photo)])
        #expect(try store.load(folder: writer) == backup)
        let candidates = store.candidates(thisWriterID: writer)
        #expect(candidates.count == 1)
        #expect(candidates.first?.isThisDevice == true)
        #expect(
            candidates.first?.summary
                == DataBackupSummary(
                    createdAt: backup.createdAt, deviceModel: "iPhone", peopleCount: 2, giftsCount: 1))
        #expect(store.uploadState(writerID: writer) == .notInICloud)
    }

    @Test func keepsThePreviousBackupAndOnlyThePhotosEitherNeeds() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = BackupSamples.backup()
        try store.write(first, writerID: writer)

        var second = first
        second.people[0] = BackupSamples.person("p-anna", "Anna", sortIndex: 0, photo: BackupSamples.otherPhoto)
        try store.write(second, writerID: writer)
        // The previous copy still needs the first photo.
        #expect(photoFiles(store, writer: writer).count == 2)

        var third = second
        third.people[0] = BackupSamples.person("p-anna", "Anna", sortIndex: 0)
        try store.write(third, writerID: writer)
        #expect(photoFiles(store, writer: writer) == [DataBackupCodec.photoFileName(for: BackupSamples.otherPhoto)])

        let previous = store.root.appending(path: writer).appending(path: BackupFolderStore.previousFileName)
        #expect(try DataBackupCodec.decode(Data(contentsOf: previous)).people[0].photo == nil)
        #expect(try store.load(folder: writer) == third)
    }

    @Test func aDamagedCurrentBackupFallsBackToThePreviousOne() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = BackupSamples.backup()
        try store.write(first, writerID: writer)
        try store.write(BackupSamples.backup(gifts: []), writerID: writer)
        let current = store.root.appending(path: writer).appending(path: BackupFolderStore.currentFileName)
        try Data("damaged".utf8).write(to: current)

        #expect(try store.load(folder: writer).gifts == first.gifts)
        #expect(store.candidates(thisWriterID: writer).first?.summary.giftsCount == 1)
    }

    @Test func aDamagedCurrentBackupNeverReplacesTheGoodPreviousOne() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = BackupSamples.backup()
        try store.write(first, writerID: writer)
        try store.write(BackupSamples.backup(gifts: []), writerID: writer)
        let folder = store.root.appending(path: writer)
        try Data("damaged".utf8).write(to: folder.appending(path: BackupFolderStore.currentFileName))
        let previous = folder.appending(path: BackupFolderStore.previousFileName)
        let goodPrevious = try Data(contentsOf: previous)

        try store.write(BackupSamples.backup(people: [], gifts: []), writerID: writer)

        #expect(try Data(contentsOf: previous) == goodPrevious)
    }

    @Test func aPhotoThatCannotBeReadFailsTheLoadUntilItArrives() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.write(BackupSamples.backup(), writerID: writer)
        let photo = store.root.appending(path: writer).appending(path: BackupFolderStore.photosFolderName)
            .appending(path: DataBackupCodec.photoFileName(for: BackupSamples.photo))
        let parked = store.root.appending(path: "parked.photo")
        try FileManager.default.moveItem(at: photo, to: parked)

        #expect(throws: (any Error).self) { try store.load(folder: writer) }
        // The restore list still shows it: its summary needs no photo.
        #expect(store.candidates(thisWriterID: writer).count == 1)

        try FileManager.default.moveItem(at: parked, to: photo)
        #expect(try store.load(folder: writer).people.first?.photo == BackupSamples.photo)
    }

    @Test func listsEveryInstallNewestFirstAndIgnoresOtherFolders() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let older = UUID().uuidString
        try store.write(BackupSamples.backup(createdAt: Date(timeIntervalSince1970: 1_000)), writerID: older)
        try store.write(BackupSamples.backup(createdAt: Date(timeIntervalSince1970: 2_000)), writerID: writer)
        try FileManager.default.createDirectory(
            at: store.root.appending(path: "not-a-backup"), withIntermediateDirectories: true)

        let candidates = store.candidates(thisWriterID: older, knownFolders: ["../escape", UUID().uuidString])
        #expect(candidates.map(\.folderName) == [writer, older])
        #expect(candidates.map(\.isThisDevice) == [false, true])
        #expect(throws: (any Error).self) { try store.write(BackupSamples.backup(), writerID: "../escape") }
    }

    @Test func anEmptiedJournalStillListsItsEarlierCopy() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let full = BackupSamples.backup()
        try store.write(full, writerID: writer)
        try store.write(BackupSamples.backup(people: [], gifts: [], selfPersonID: nil), writerID: writer)

        let candidates = store.candidates(thisWriterID: UUID().uuidString)
        #expect(candidates.count == 2)
        let earlier = try #require(candidates.first { $0.isPreviousCopy })
        #expect(earlier.summary.giftsCount == 1)
        #expect(try store.load(folder: writer, previousCopy: true) == full)

        try store.delete(folder: writer, previousCopyOnly: true)
        #expect(store.candidates(thisWriterID: UUID().uuidString).map(\.isPreviousCopy) == [false])
    }

    @Test func deletesOneInstallsBackup() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.write(BackupSamples.backup(), writerID: writer)
        try store.delete(folder: writer)
        #expect(store.candidates(thisWriterID: writer).isEmpty)
        #expect(!store.hasBackup(writerID: writer))
    }
}

// MARK: - iCloud backup service

@MainActor
struct ICloudBackupServiceTests {
    private func makeSettings() -> (BackupSettings, UserDefaults, String) {
        let suite = "ICloudBackupServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (BackupSettings(defaults: defaults, prefix: "test."), defaults, suite)
    }

    private func makeService(
        root: URL?, settings: BackupSettings, analytics: AnalyticsGateway = NoopAnalyticsGateway()
    ) -> ICloudBackupService {
        ICloudBackupService(
            settings: settings, analytics: analytics, debounce: .zero,
            locateStore: { root.map { BackupFolderStore(root: $0, usesFileCoordination: false) } })
    }

    @Test func writesOnlyWhenTheContentChanges() async throws {
        let root = try makeTemporaryDirectory()
        let (settings, defaults, suite) = makeSettings()
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        var backup = BackupSamples.backup(createdAt: Date(timeIntervalSince1970: 1_000))
        let service = makeService(root: root, settings: settings)
        await service.start { backup }
        await service.backUpNow()
        #expect(service.availability == .available)
        #expect(service.lastBackupAt == Date(timeIntervalSince1970: 1_000))

        // Same records later: nothing new to write.
        backup.createdAt = Date(timeIntervalSince1970: 2_000)
        await service.backUpNow()
        #expect(service.lastBackupAt == Date(timeIntervalSince1970: 1_000))

        backup.gifts = []
        await service.backUpNow()
        #expect(service.lastBackupAt == Date(timeIntervalSince1970: 2_000))
        let store = BackupFolderStore(root: root, usesFileCoordination: false)
        #expect(try store.load(folder: settings.writerID).gifts.isEmpty)
    }

    @Test func aFreshInstallWithAnEmptyJournalWritesNothing() async throws {
        let root = try makeTemporaryDirectory()
        let (settings, defaults, suite) = makeSettings()
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let service = makeService(root: root, settings: settings)
        await service.start { BackupSamples.backup(people: [], gifts: [], selfPersonID: nil) }
        await service.backUpNow()
        #expect(service.lastBackupAt == nil)
        #expect(!BackupFolderStore(root: root, usesFileCoordination: false).hasBackup(writerID: settings.writerID))
    }

    @Test func writesNothingWithoutAJournalSnapshotOrWhenOff() async throws {
        let root = try makeTemporaryDirectory()
        let (settings, defaults, suite) = makeSettings()
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let service = makeService(root: root, settings: settings)
        await service.start { nil }
        await service.backUpNow()
        #expect(service.lastBackupAt == nil)

        let off = makeService(root: root, settings: settings)
        off.setEnabled(false)
        await off.start { BackupSamples.backup() }
        await off.backUpNow()
        #expect(off.lastBackupAt == nil)
        #expect(!settings.isEnabled)
    }

    @Test func withoutICloudItIsUnavailable() async {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = makeService(root: nil, settings: settings)
        await service.start { BackupSamples.backup() }
        #expect(service.availability == .unavailable)
        #expect(
            BackupStatusText.describe(service).contains(
                String(localized: "iCloud is not available. To keep a backup, sign in to iCloud in the Settings app and turn on iCloud Drive.")))
    }

    @Test func offersTheNewestBackupFromAnotherInstallUntilDismissed() async throws {
        let root = try makeTemporaryDirectory()
        let (settings, defaults, suite) = makeSettings()
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = BackupFolderStore(root: root, usesFileCoordination: false)
        let oldInstall = UUID().uuidString
        try store.write(BackupSamples.backup(), writerID: oldInstall)
        try store.write(BackupSamples.backup(createdAt: .distantFuture), writerID: settings.writerID)

        let service = makeService(root: root, settings: settings)
        await service.refreshCandidates()
        #expect(service.candidates.count == 2)
        #expect(service.restoreOffer?.folderName == oldInstall)
        #expect(try await service.loadBackup(try #require(service.restoreOffer)) == BackupSamples.backup())

        service.dismissRestoreOffer()
        #expect(service.restoreOffer == nil)
        #expect(settings.isRestoreOfferDismissed)
    }

    @Test func deletingThisInstallsBackupWritesAFullOneNextTime() async throws {
        let root = try makeTemporaryDirectory()
        let (settings, defaults, suite) = makeSettings()
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let service = makeService(root: root, settings: settings)
        await service.start { BackupSamples.backup() }
        await service.backUpNow()
        await service.refreshCandidates()
        try await service.deleteBackup(try #require(service.candidates.first))
        #expect(service.candidates.isEmpty)
        #expect(service.lastBackupAt == nil)

        await service.backUpNow()
        #expect(BackupFolderStore(root: root, usesFileCoordination: false).hasBackup(writerID: settings.writerID))
    }

    @Test func aBackupDeletedElsewhereIsWrittenAgainEvenWithoutChanges() async throws {
        let root = try makeTemporaryDirectory()
        let (settings, defaults, suite) = makeSettings()
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let service = makeService(root: root, settings: settings)
        await service.start { BackupSamples.backup() }
        await service.backUpNow()
        let store = BackupFolderStore(root: root, usesFileCoordination: false)
        // Another device removes this install's backup from the shared iCloud folder.
        try store.delete(folder: settings.writerID)

        await service.backUpNow()
        #expect(store.hasBackup(writerID: settings.writerID))
    }

    @Test func togglingIsTracked() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let analytics = RecordingAnalyticsGateway()
        let service = makeService(root: nil, settings: settings, analytics: analytics)
        service.setEnabled(false)
        service.setEnabled(false)
        service.setEnabled(true)
        #expect(analytics.events == [.iCloudBackupToggled(isOn: false), .iCloudBackupToggled(isOn: true)])
    }

    @Test func eachInstallKeepsItsOwnFolder() {
        let (first, firstDefaults, firstSuite) = makeSettings()
        let (second, secondDefaults, secondSuite) = makeSettings()
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        #expect(first.writerID == first.writerID)
        #expect(first.writerID != second.writerID)
        #expect(UUID(uuidString: first.writerID) != nil)
    }
}

// MARK: - Status text

struct BackupStatusTextTests {
    private func describe(
        isEnabled: Bool = true, availability: ICloudBackupService.Availability = .available,
        isBackingUp: Bool = false, lastBackupAt: Date? = nil, uploadState: BackupUploadState? = nil,
        lastWriteFailed: Bool = false
    ) -> String {
        BackupStatusText.describe(
            isEnabled: isEnabled, availability: availability, isBackingUp: isBackingUp, lastBackupAt: lastBackupAt,
            uploadState: uploadState, lastWriteFailed: lastWriteFailed)
    }

    @Test func saysWhyTheDataIsNotInICloud() {
        #expect(
            describe(isEnabled: false)
                == String(
                    localized:
                        "iCloud backup is off. New changes stay only on this device. Earlier backups remain in iCloud until you delete them in Restore from iCloud."
                ))
        #expect(describe(availability: .checking) == String(localized: "Checking iCloud…"))
        #expect(
            describe(lastWriteFailed: true)
                == String(localized: "Couldn't save the backup. Check that this device has free space."))
        #expect(
            describe(lastBackupAt: .now, uploadState: .failed)
                == String(localized: "Couldn't upload the backup. Check that your iCloud storage is not full."))
    }

    @Test func showsTheLastBackupOnceThereIsOne() {
        #expect(describe() == String(localized: "Your data is backed up to iCloud after each change."))
        #expect(describe(isBackingUp: true) == String(localized: "Backing up…"))
        let uploaded = describe(lastBackupAt: .now.addingTimeInterval(-120), uploadState: .uploaded)
        let uploading = describe(lastBackupAt: .now.addingTimeInterval(-120), uploadState: .uploading)
        #expect(uploaded != uploading)
        #expect(uploading.hasPrefix(String(uploaded.dropLast())))
    }
}

// MARK: - Composition

@MainActor
struct DataBackupCompositionTests {
    private func makeEmptyComposition(
        preferences: TestPreferencesGateway? = nil,
        analytics: AnalyticsGateway = NoopAnalyticsGateway()
    ) throws -> AppComposition {
        AppComposition(
            store: try SwiftDataStore(inMemory: true), preferences: preferences ?? TestPreferencesGateway(),
            intelligence: TestIntelligenceGateway(), analytics: analytics)
    }

    @Test func backupHoldsTheJournalAndItsPreferences() throws {
        let composition = try makeTestComposition()
        composition.setDefaultCurrency(.rub)
        let backup = try #require(composition.makeBackup(createdAt: Date(timeIntervalSince1970: 1)))
        #expect(backup.people.count == 10)
        #expect(backup.gifts.count == 12)
        #expect(backup.selfPersonID == "anton")
        #expect(backup.defaultCurrency == .rub)
        #expect(backup.createdAt == Date(timeIntervalSince1970: 1))
    }

    @Test func noBackupWhileTheJournalCannotBeLoaded() throws {
        struct LoadFailed: Error {}
        final class FailingGifts: GiftGateway {
            func loadGifts() throws -> [Gift] { throw LoadFailed() }
            func save(_ gift: Gift) throws {}
            func deleteGift(id: String) throws {}
        }
        let store = try SwiftDataStore(inMemory: true, seed: true)
        let composition = AppComposition(
            store: store, preferences: TestPreferencesGateway(), intelligence: TestIntelligenceGateway(),
            giftGateway: FailingGifts())
        #expect(composition.makeBackup() == nil)
    }

    @Test func restoreIntoAnEmptyJournalBringsBackItsPreferences() throws {
        let preferences = TestPreferencesGateway()
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeEmptyComposition(preferences: preferences, analytics: analytics)
        #expect(composition.data.isJournalEmpty)

        let result = composition.restore(BackupSamples.backup(), source: .iCloud)

        guard case .restored(let summary) = result else {
            Issue.record("The restore failed")
            return
        }
        #expect(summary.restoredIntoEmptyJournal)
        #expect(composition.data.people.map(\.id) == ["p-anna", "p-maria"])
        #expect(composition.data.gifts.map(\.id) == ["g-1"])
        #expect(composition.data.selfPersonID == "p-anna")
        #expect(preferences.selfPersonID == "p-anna")
        #expect(composition.defaultCurrency == .rub)
        #expect(preferences.currencyCode == "RUB")
        #expect(!composition.data.isJournalEmpty)
        #expect(
            analytics.events.contains(
                .dataRestored(source: .iCloud, peopleAdded: 2, giftsAdded: 1, intoEmptyJournal: true)))
        #expect(!analytics.eventNames.contains("currency_changed"))
    }

    @Test func restoreNextToExistingRecordsKeepsTheUsersPreferences() throws {
        let composition = try makeTestComposition()
        composition.setDefaultCurrency(.usd)
        let result = composition.restore(BackupSamples.backup(defaultCurrency: .rub), source: .file)
        guard case .restored(let summary) = result else {
            Issue.record("The restore failed")
            return
        }
        #expect(!summary.restoredIntoEmptyJournal)
        #expect(composition.defaultCurrency == .usd)
        #expect(composition.data.selfPersonID == "anton")
        #expect(composition.data.people.count == 12)
        #expect(composition.data.gifts.count == 13)
    }

    @Test func exportWritesOneFileThatReadsBackAsTheSameBackup() async throws {
        let analytics = RecordingAnalyticsGateway()
        let composition = try makeTestComposition(analytics: analytics)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let url = try await composition.exportBackupFile(now: now)

        #expect(url.pathExtension == DataBackupCodec.fileExtension)
        let read = try await composition.readBackupFile(at: url)
        #expect(read == composition.makeBackup(createdAt: now))
        #expect(analytics.events.contains(.dataExported(peopleCount: 10, giftsCount: 12)))

        // Importing the export into another journal restores everything.
        let empty = try makeEmptyComposition()
        guard case .restored(let summary) = empty.restore(read, source: .file) else {
            Issue.record("The restore failed")
            return
        }
        #expect(summary.giftsAdded == 12)
        #expect(empty.data.gifts.map(\.id).sorted() == composition.data.gifts.map(\.id).sorted())
        #expect(empty.data.people.map(\.id) == composition.data.people.map(\.id))
    }

    @Test func newEventsCarryCountsOnly() {
        #expect(
            AnalyticsEvent.dataExported(peopleCount: 2, giftsCount: 3).properties == [
                "people_count": .int(2), "gifts_count": .int(3)
            ])
        #expect(
            AnalyticsEvent.dataRestored(source: .file, peopleAdded: 1, giftsAdded: 4, intoEmptyJournal: false).properties
                == [
                    "source": .string("file"), "people_added": .int(1), "gifts_added": .int(4),
                    "into_empty_journal": .bool(false)
                ])
        #expect(AnalyticsEvent.iCloudBackupToggled(isOn: true).name == "icloud_backup_toggled")
    }
}
