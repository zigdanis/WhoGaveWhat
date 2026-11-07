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
        if itemExists(at: current), let json = try? coordinatedRead(current) {
            try coordinatedWrite(json, to: previous)
            previousJSON = json
        } else if itemExists(at: previous) {
            previousJSON = try? coordinatedRead(previous)
        }
        try coordinatedWrite(encoded.json, to: current)

        // Photos neither copy refers to any more, e.g. a replaced or removed portrait.
        let keep = Set(encoded.photos.keys).union(previousJSON.map(DataBackupCodec.referencedPhotoFiles) ?? [])
        let files = (try? FileManager.default.contentsOfDirectory(atPath: photos.path())) ?? []
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
    /// may not have reached this device yet; reading them downloads them.
    func candidates(thisWriterID: String, knownFolders: Set<String> = []) -> [BackupCandidate] {
        let listed = (try? FileManager.default.contentsOfDirectory(atPath: root.path())) ?? []
        let folders = knownFolders.union(listed).filter(Self.isSafeFolderName)
        return folders.compactMap { folder -> BackupCandidate? in
            guard let json = try? readNewestJSON(folder: folder),
                let summary = try? DataBackupCodec.decodeSummary(json)
            else { return nil }
            return BackupCandidate(folderName: folder, summary: summary, isThisDevice: folder == thisWriterID)
        }
        .sorted { $0.summary.createdAt > $1.summary.createdAt }
    }

    /// The backup in `folder`, with its photos. The previous copy stands in when the current one cannot be read.
    func load(folder: String) throws -> DataBackup {
        guard Self.isSafeFolderName(folder) else { throw DataBackupError.unreadable }
        let json = try readNewestJSON(folder: folder)
        let photos = root.appending(path: folder).appending(path: Self.photosFolderName, directoryHint: .isDirectory)
        return try DataBackupCodec.decode(json) { name in
            try? coordinatedRead(photos.appending(path: name))
        }
    }

    /// Removes one install's backup from iCloud.
    func delete(folder: String) throws {
        guard Self.isSafeFolderName(folder) else { throw CocoaError(.fileWriteInvalidFileName) }
        try coordinatedDelete(root.appending(path: folder, directoryHint: .isDirectory))
    }

    /// Whether iCloud has this install's current backup yet.
    func uploadState(writerID: String) -> BackupUploadState {
        guard Self.isSafeFolderName(writerID) else { return .notInICloud }
        let url = root.appending(path: writerID).appending(path: Self.currentFileName)
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
            .ubiquitousItemUploadingErrorKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true else {
            return .notInICloud
        }
        if values.ubiquitousItemUploadingError != nil { return .failed }
        return values.ubiquitousItemIsUploaded == true ? .uploaded : .uploading
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
        if FileManager.default.fileExists(atPath: url.path()) { return true }
        guard usesFileCoordination else { return false }
        let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: placeholder.path())
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

    var id: String { folderName }
}

enum BackupUploadState: Equatable, Sendable {
    case uploaded
    case uploading
    /// iCloud refused the upload, most often because the user's iCloud storage is full.
    case failed
    /// Not an iCloud file, e.g. a test folder.
    case notInICloud
}
