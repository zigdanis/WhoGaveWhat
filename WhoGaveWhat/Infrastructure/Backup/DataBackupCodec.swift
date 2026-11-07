import CryptoKit
import Foundation

/// The JSON form of a `DataBackup`, shared by the exported file and the iCloud backup.
///
/// Version 1 layout:
/// ```json
/// {"format": "whogavewhat-backup", "version": 1, "createdAt": "…", "appVersion": "1.3.0", "device": "iPhone",
///  "preferences": {"defaultCurrency": "RUB", "selfPersonID": "anton"},
///  "people": [{"id": "anton", "name": "Anton", "colorHex": 1185308, "sortIndex": 0, "photo": "<base64>"}],
///  "gifts": [{"id": "g1", "giverID": "maria", "recipientID": "anton", "currency": "RUB", …}]}
/// ```
/// A person's photo is either inline (`photo`, base64) or, in the iCloud backup, a separate file named by
/// its content (`photoFile`), so a change to a gift does not upload every photo again. Readers ignore keys
/// they do not know; a later format that older readers must not read raises `version`.
enum DataBackupCodec {
    static let format = "whogavewhat-backup"
    static let currentVersion = 1
    /// The extension of exported files, declared as the app's own document type in Info.plist.
    static let fileExtension = "whogavewhat"

    enum PhotoStorage {
        /// Photos inside the JSON, for a single self-contained file.
        case inline
        /// Photos as separate files; `encode` returns them keyed by `photoFileName(for:)`.
        case external
    }

    struct Encoded {
        let json: Data
        /// The photo files the JSON refers to, empty for `.inline`.
        let photos: [String: Data]
    }

    static func encode(_ backup: DataBackup, photos storage: PhotoStorage) throws -> Encoded {
        var photoFiles: [String: Data] = [:]
        let people = backup.people.map { person -> PersonRecord in
            var record = PersonRecord(
                id: person.id, name: person.name, colorHex: person.colorHex, sortIndex: person.sortIndex,
                photo: nil, photoFile: nil)
            if let photo = person.photo {
                switch storage {
                case .inline:
                    record.photo = photo
                case .external:
                    let name = photoFileName(for: photo)
                    photoFiles[name] = photo
                    record.photoFile = name
                }
            }
            return record
        }
        let file = FileRecord(
            format: format,
            version: currentVersion,
            createdAt: backup.createdAt,
            appVersion: backup.appVersion,
            device: backup.deviceModel,
            preferences: PreferencesRecord(
                defaultCurrency: backup.defaultCurrency?.code, selfPersonID: backup.selfPersonID),
            people: people,
            gifts: backup.gifts.map(GiftRecord.init))
        return Encoded(json: try makeEncoder().encode(file), photos: photoFiles)
    }

    /// Reads and checks a backup. `photo` supplies the content of a `photoFile`; nil means no photo, and an
    /// error it throws fails the decoding. Without `photo`, photo files are left out (the restore list's summary).
    static func decode(_ data: Data, photo: (String) throws -> Data? = { _ in nil }) throws -> DataBackup {
        let decoder = makeDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw DataBackupError.unreadable
        }
        guard header.format == format else { throw DataBackupError.unreadable }
        guard header.version <= currentVersion else { throw DataBackupError.newerVersion(header.version) }

        let file: FileRecord
        do {
            file = try decoder.decode(FileRecord.self, from: data)
        } catch {
            throw DataBackupError.unreadable
        }
        let gifts = try file.gifts.map { record -> DataBackup.Gift in
            guard let currency = SupportedCurrency(rawValue: record.currency) else {
                throw DataBackupError.inconsistent("unknown_currency")
            }
            return record.gift(currency: currency)
        }
        let people = try file.people.map { record in
            var photoData = record.photo
            if photoData == nil, let name = record.photoFile, isSafePhotoFileName(name) {
                photoData = try photo(name)
            }
            return DataBackup.Person(
                id: record.id, name: record.name, colorHex: record.colorHex, sortIndex: record.sortIndex,
                photo: photoData)
        }
        return try DataBackup(
            createdAt: file.createdAt,
            appVersion: file.appVersion ?? "",
            deviceModel: file.device ?? "",
            defaultCurrency: file.preferences?.defaultCurrency.flatMap(SupportedCurrency.init(rawValue:)),
            selfPersonID: file.preferences?.selfPersonID,
            people: people,
            gifts: gifts
        ).validated()
    }

    /// The summary the restore list shows, read without loading any photo.
    static func decodeSummary(_ data: Data) throws -> DataBackupSummary {
        let backup = try decode(data)
        return DataBackupSummary(
            createdAt: backup.createdAt, deviceModel: backup.deviceModel,
            peopleCount: backup.people.count, giftsCount: backup.gifts.count)
    }

    /// The photo files a backup's JSON refers to, for removing the ones no backup needs any more.
    static func referencedPhotoFiles(in data: Data) -> Set<String> {
        guard let file = try? makeDecoder().decode(PhotoReferences.self, from: data) else { return [] }
        return Set(file.people.compactMap(\.photoFile))
    }

    /// A photo's file name: its SHA-256, so equal photos share one file and a changed photo gets a new one.
    static func photoFileName(for photo: Data) -> String {
        SHA256.hash(data: photo).map { String(format: "%02x", $0) }.joined() + ".photo"
    }

    /// Only names this codec writes, so a damaged or crafted backup cannot point outside its folder.
    static func isSafePhotoFileName(_ name: String) -> Bool {
        let stem = name.hasSuffix(".photo") ? String(name.dropLast(6)) : ""
        return stem.count == 64 && stem.allSatisfy(\.isHexDigit)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestampFormatter.string(from: date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = timestampFormatter.date(from: text) ?? plainTimestampFormatter.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date")
        }
        return decoder
    }

    /// ISO 8601 in UTC with milliseconds, readable in the exported file.
    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - File records

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    private struct PhotoReferences: Decodable {
        struct Person: Decodable { let photoFile: String? }
        let people: [Person]
    }

    private struct FileRecord: Codable {
        let format: String
        let version: Int
        let createdAt: Date
        let appVersion: String?
        let device: String?
        let preferences: PreferencesRecord?
        let people: [PersonRecord]
        let gifts: [GiftRecord]
    }

    private struct PreferencesRecord: Codable {
        let defaultCurrency: String?
        let selfPersonID: String?
    }

    private struct PersonRecord: Codable {
        let id: String
        let name: String
        let colorHex: UInt
        let sortIndex: Int
        var photo: Data?
        var photoFile: String?
    }

    private struct GiftRecord: Codable {
        let id: String
        let emoji: String
        let name: String
        let giverID: String
        let recipientID: String
        let paidByYou: Bool
        let occasion: String
        let date: Date
        let value: Double
        let currency: String
        let createdAt: Date
        let emojiPickedByUser: Bool?
        let lastSavedAt: Date?

        init(_ gift: DataBackup.Gift) {
            id = gift.id
            emoji = gift.emoji
            name = gift.name
            giverID = gift.giverID
            recipientID = gift.recipientID
            paidByYou = gift.paidByYou
            occasion = gift.occasion
            date = gift.date
            value = gift.value
            currency = gift.currency.code
            createdAt = gift.createdAt
            emojiPickedByUser = gift.emojiPickedByUser
            lastSavedAt = gift.lastSavedAt
        }

        func gift(currency: SupportedCurrency) -> DataBackup.Gift {
            DataBackup.Gift(
                id: id, emoji: emoji, name: name, giverID: giverID, recipientID: recipientID,
                paidByYou: paidByYou, occasion: occasion, date: date, value: value, currency: currency,
                createdAt: createdAt, emojiPickedByUser: emojiPickedByUser ?? false, lastSavedAt: lastSavedAt)
        }
    }
}

/// What a backup holds, for choosing one to restore.
struct DataBackupSummary: Equatable, Sendable {
    let createdAt: Date
    let deviceModel: String
    let peopleCount: Int
    let giftsCount: Int

    var isEmpty: Bool { peopleCount == 0 && giftsCount == 0 }
}
