import Foundation

/// Everything the user entered, as one value: the people with their photos and order, every gift with
/// its own currency, and the preferences that refer to them. The iCloud backup and the exported file
/// both hold one; restoring adds it to the journal without changing or deleting what is already there.
struct DataBackup: Equatable, Sendable {
    struct Person: Equatable, Sendable {
        let id: String
        let name: String
        let colorHex: UInt
        /// The person's place in the People list, which the domain `Person` does not carry.
        let sortIndex: Int
        let photo: Data?
    }

    struct Gift: Equatable, Sendable {
        let id: String
        let emoji: String
        let name: String
        let giverID: String
        let recipientID: String
        let paidByYou: Bool
        let occasion: String
        let date: Date
        let value: Double
        let currency: SupportedCurrency
        let createdAt: Date
        let emojiPickedByUser: Bool
        let lastSavedAt: Date?
    }

    var createdAt: Date
    /// The app version that wrote it, for support questions only; reading never depends on it.
    var appVersion: String
    /// "iPhone" or "iPad", so the restore list can tell backups from different devices apart.
    var deviceModel: String
    var defaultCurrency: SupportedCurrency?
    var selfPersonID: String?
    var people: [Person]
    var gifts: [Gift]

    var isEmpty: Bool { people.isEmpty && gifts.isEmpty }

    /// The largest amount a restored gift may have: any amount the app can edit (it converts amounts to
    /// `Int`), so every saved gift round-trips, while a damaged file cannot store one that would crash.
    static let maximumValue: Double = 9_000_000_000_000_000_000

    /// The same records and preferences, ignoring when and where they were written: two backups with
    /// equal content need only one write.
    func hasSameContent(as other: DataBackup) -> Bool {
        people == other.people && gifts == other.gifts && defaultCurrency == other.defaultCurrency
            && selfPersonID == other.selfPersonID
    }
}

/// Why a backup could not be read. Nothing is restored from a backup that fails any check.
enum DataBackupError: Error, Equatable {
    /// Not a Who Gave What backup at all, or damaged beyond reading.
    case unreadable
    /// Written by a newer version of the app, in a format this version does not know.
    case newerVersion(Int)
    /// Readable, but its records contradict each other, e.g. a gift from a person it does not contain.
    case inconsistent(String)
}

extension DataBackup {
    /// Checks the rules every restore relies on: unique ids, gifts between two different people the
    /// backup contains, and a viewpoint that is one of its people.
    func validated() throws -> DataBackup {
        var personIDs = Set<String>()
        for person in people {
            guard !person.id.isEmpty, personIDs.insert(person.id).inserted else {
                throw DataBackupError.inconsistent("duplicate_person")
            }
        }
        var giftIDs = Set<String>()
        for gift in gifts {
            // The app turns amounts into whole numbers for editing; anything beyond this is not a real amount.
            guard gift.value.isFinite, abs(gift.value) <= DataBackup.maximumValue else {
                throw DataBackupError.inconsistent("value_out_of_range")
            }
            guard !gift.id.isEmpty, giftIDs.insert(gift.id).inserted else {
                throw DataBackupError.inconsistent("duplicate_gift")
            }
            guard personIDs.contains(gift.giverID), personIDs.contains(gift.recipientID) else {
                throw DataBackupError.inconsistent("missing_person")
            }
            guard gift.giverID != gift.recipientID else {
                throw DataBackupError.inconsistent("same_person")
            }
        }
        var result = self
        // A viewpoint without its person is dropped rather than failing the whole backup.
        if let selfPersonID, !personIDs.contains(selfPersonID) { result.selfPersonID = nil }
        return result
    }
}

/// Where a restore came from, for analytics.
enum DataRestoreSource: String, Equatable {
    case iCloud = "icloud"
    case file
}

/// What a restore added. Records already in the journal are kept as they are and counted as skipped.
struct DataRestoreSummary: Equatable {
    var peopleAdded = 0
    var giftsAdded = 0
    /// Backup people that matched one already in the journal, by id or by name.
    var peopleMatched = 0
    /// Backup gifts already in the journal.
    var giftsAlreadyHere = 0
    /// Backup gifts between two backup people who are one person here (same name), so they cannot be added.
    var giftsWithoutPlace = 0
    /// Whether the journal was empty, so the backup's preferences were applied too.
    var restoredIntoEmptyJournal = false
    /// The backup's "This is me" person as stored here, which may be another id when two backup people
    /// matched one by name; nil when the backup has none.
    var restoredSelfPersonID: String?

    var addedAnything: Bool { peopleAdded > 0 || giftsAdded > 0 }
}
