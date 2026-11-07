import Foundation

/// The backups in one folder, one subfolder per install:
/// `<root>/<writerID>/backup.json`, `backup-previous.json` and `photos/<sha256>.photo`.
///
/// In the app the root is `Backups` at the top of the app's iCloud container, outside its `Documents`
/// folder, so iCloud keeps it with the user's account but iCloud Drive and Files never show it; only
/// Settings → iCloud → Manage Storage lists its size. Each install writes only its own subfolder, so two
/// devices, or a reinstall, never write the same file, and a reinstalled app cannot overwrite the backup
/// it should restore from. Tests use a temporary folder without file coordination.
struct BackupFolderStore: Sendable {
    static let currentFileName = "backup.json"
    static let previousFileName = "backup-previous.json"
    static let photosFolderName = "photos"

    let root: URL
    /// iCloud files are read and written through `NSFileCoordinator`, which also downloads a file that is
    /// only in iCloud before reading it.
    let usesFileCoordination: Bool
    /// How long a read may wait for iCloud to download a file before giving up.
    var readTimeout: TimeInterval = 30

    // MARK: - Writing

    /// Writes `backup` as this install's current backup and keeps the one it replaces as the previous,
    /// so a bad write can never leave this install without a good copy. Photos are written first and the
    /// JSON last, so a backup never refers to a photo that is not there yet.
    func write(_ backup: DataBackup, writerID: String) throws {
        guard Self.isSafeFolderName(writerID) else { throw CocoaError(.fileWriteInvalidFileName) }
        let folder = root.appending(path: writerID, directoryHint: .isDirectory)
        let photos = folder.appending(path: Self.photosFolderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)

        let encoded = try DataBackupCodec.encode(backup, photos: .external)
        for (name, data) in encoded.photos {
            let url = photos.appending(path: name)
            if !itemExists(at: url) { try coordinatedWrite(data, to: url) }
        }

        let current = folder.appending(path: Self.currentFileName)
        let previous = folder.appending(path: Self.previousFileName)
        var previousJSON: Data?
        // Only a readable backup becomes the previous one; a damaged current file never replaces a good
        // previous copy, so a failed write below still leaves one backup to restore.
        if itemExists(at: current), let json = try? coordinatedRead(current),
            (try? DataBackupCodec.decodeSummary(json)) != nil
        {
            try coordinatedWrite(json, to: previous)
            previousJSON = json
        } else if itemExists(at: previous) {
            previousJSON = try? coordinatedRead(previous)
        }
        try coordinatedWrite(encoded.json, to: current)

        // Photos neither copy refers to any more, e.g. a replaced or removed portrait.
        let keep = Set(encoded.photos.keys).union(previousJSON.map(DataBackupCodec.referencedPhotoFiles) ?? [])
        let files = (try? FileManager.default.contentsOfDirectory(atPath: photos.path(percentEncoded: false))) ?? []
        for name in files where DataBackupCodec.isSafePhotoFileName(name) && !keep.contains(name) {
            try? coordinatedDelete(photos.appending(path: name))
        }
    }

    /// Whether this install has written a backup yet.
    func hasBackup(writerID: String) -> Bool {
        guard Self.isSafeFolderName(writerID) else { return false }
        return itemExists(at: root.appending(path: writerID).appending(path: Self.currentFileName))
    }

    // MARK: - Reading

    /// Every readable backup, newest first. `knownFolders` adds folders iCloud reported but whose files
    /// may not have reached this device yet; reading them downloads them. When an install's journal was
    /// emptied, its previous, non-empty copy is listed too, so deleting everything can still be undone.
    func candidates(thisWriterID: String, knownFolders: Set<String> = []) -> [BackupCandidate] {
        let listed = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        let folders = knownFolders.union(listed).filter(Self.isSafeFolderName)
        return folders.flatMap { folder -> [BackupCandidate] in
            guard let json = try? readNewestJSON(folder: folder),
                let summary = try? DataBackupCodec.decodeSummary(json)
            else { return [] }
            let isThisDevice = folder == thisWriterID
            var found = [BackupCandidate(folderName: folder, summary: summary, isThisDevice: isThisDevice)]
            if summary.isEmpty, let previous = try? readPreviousJSON(folder: folder),
                let previousSummary = try? DataBackupCodec.decodeSummary(previous), !previousSummary.isEmpty
            {
                found.append(
                    BackupCandidate(
                        folderName: folder, summary: previousSummary, isThisDevice: isThisDevice,
                        isPreviousCopy: true))
            }
            return found
        }
        .sorted { $0.summary.createdAt > $1.summary.createdAt }
    }

    /// The backup in `folder`, with its photos. The previous copy stands in when the current one cannot be read.
    /// A photo that cannot be read, e.g. one iCloud has not downloaded yet, fails the whole load: a restore
    /// without it could not be repaired later, since restoring again skips people already in the journal.
    func load(folder: String, previousCopy: Bool = false) throws -> DataBackup {
        guard Self.isSafeFolderName(folder) else { throw DataBackupError.unreadable }
        let json = try previousCopy ? readPreviousJSON(folder: folder) : readNewestJSON(folder: folder)
        let photos = root.appending(path: folder).appending(path: Self.photosFolderName, directoryHint: .isDirectory)
        return try DataBackupCodec.decode(json) { name in
            try coordinatedRead(photos.appending(path: name))
        }
    }

    /// Removes one install's backup from iCloud, or only its previous copy.
    func delete(folder: String, previousCopyOnly: Bool = false) throws {
        guard Self.isSafeFolderName(folder) else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = root.appending(path: folder, directoryHint: .isDirectory)
        try coordinatedDelete(previousCopyOnly ? url.appending(path: Self.previousFileName) : url)
    }

    /// Whether iCloud has this install's whole current backup yet: its JSON and every photo it refers to.
    func uploadState(writerID: String) -> BackupUploadState {
        guard Self.isSafeFolderName(writerID) else { return .notInICloud }
        let folder = root.appending(path: writerID, directoryHint: .isDirectory)
        let current = folder.appending(path: Self.currentFileName)
        let photos = folder.appending(path: Self.photosFolderName, directoryHint: .isDirectory)
        let referenced = (try? Data(contentsOf: current)).map(DataBackupCodec.referencedPhotoFiles) ?? []
        let states = ([current] + referenced.sorted().map { photos.appending(path: $0) }).map(Self.uploadState(of:))
        if states.contains(.notInICloud) { return .notInICloud }
        if states.contains(.failed) { return .failed }
        return states.contains(.uploading) ? .uploading : .uploaded
    }

    private static func uploadState(of url: URL) -> BackupUploadState {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true else {
            return .notInICloud
        }
        if values.ubiquitousItemUploadingError != nil { return .failed }
        return values.ubiquitousItemIsUploaded == true ? .uploaded : .uploading
    }

    private func readPreviousJSON(folder: String) throws -> Data {
        let url = root.appending(path: folder, directoryHint: .isDirectory).appending(path: Self.previousFileName)
        guard itemExists(at: url) else { throw CocoaError(.fileReadNoSuchFile) }
        return try coordinatedRead(url)
    }

    private func readNewestJSON(folder: String) throws -> Data {
        let base = root.appending(path: folder, directoryHint: .isDirectory)
        var lastError: Error = CocoaError(.fileReadNoSuchFile)
        for name in [Self.currentFileName, Self.previousFileName] {
            let url = base.appending(path: name)
            guard itemExists(at: url) else { continue }
            do {
                let json = try coordinatedRead(url)
                _ = try DataBackupCodec.decodeSummary(json)
                return json
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Install folders are UUIDs; anything else in the root is not a backup.
    static func isSafeFolderName(_ name: String) -> Bool {
        UUID(uuidString: name) != nil
    }

    // MARK: - Files

    /// A file that is in iCloud but not downloaded yet shows locally as a hidden `.<name>.icloud` placeholder.
    private func itemExists(at url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return true }
        guard usesFileCoordination else { return false }
        let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: placeholder.path(percentEncoded: false))
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        guard usesFileCoordination else { return try Data(contentsOf: url) }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let coordinator = NSFileCoordinator()
        // A read waits for the download; without a network it would wait for good.
        let timeout = DispatchWorkItem { coordinator.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + readTimeout, execute: timeout)
        defer { timeout.cancel() }
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        guard usesFileCoordination else { return try data.write(to: url, options: .atomic) }
        var coordinationError: NSError?
        var result: Result<Void, Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    private func coordinatedDelete(_ url: URL) throws {
        guard usesFileCoordination else { return try FileManager.default.removeItem(at: url) }
        var coordinationError: NSError?
        var result: Result<Void, Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            result = Result { try FileManager.default.removeItem(at: url) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}

/// One install's backup, as the restore list shows it.
struct BackupCandidate: Identifiable, Equatable, Sendable {
    let folderName: String
    let summary: DataBackupSummary
    /// Written by this install of the app.
    let isThisDevice: Bool
    /// The copy before the latest one, listed when the latest is empty.
    var isPreviousCopy = false

    var id: String { isPreviousCopy ? folderName + "/previous" : folderName }
}

enum BackupUploadState: Equatable, Sendable {
    case uploaded
    case uploading
    /// iCloud refused the upload, most often because the user's iCloud storage is full.
    case failed
    /// Not an iCloud file, e.g. a test folder.
    case notInICloud
}
