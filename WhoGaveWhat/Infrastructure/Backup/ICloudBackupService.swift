import CryptoKit
import Foundation
import Observation
import UIKit

/// Keeps a copy of the journal in the user's iCloud, so deleting the app or changing phones does not lose it.
///
/// After every change the app makes (and once per launch) it waits a few seconds for more changes, then
/// writes this install's backup with `BackupFolderStore`, unless the content is the same as the last
/// backup it wrote. iCloud uploads the files in its own time; `uploadState` says whether it has. Nothing
/// is written before the journal has loaded, while loading fails, or for an empty journal on an install
/// that has no backup yet, so a fresh install never adds an empty backup next to the one it should restore.
@MainActor
@Observable
final class ICloudBackupService {
    enum Availability: Equatable {
        case checking
        case available
        /// No iCloud account, iCloud Drive is off for the app, or the app has no iCloud container.
        case unavailable
    }

    private(set) var availability: Availability = .checking
    private(set) var isEnabled: Bool
    private(set) var isBackingUp = false
    private(set) var lastBackupAt: Date?
    private(set) var uploadState: BackupUploadState?
    /// The last attempt to write the backup failed, e.g. the device is out of space.
    private(set) var lastWriteFailed = false
    /// Every backup found in iCloud, newest first, after `refreshCandidates()`.
    private(set) var candidates: [BackupCandidate] = []
    private(set) var isLoadingCandidates = false
    /// The user chose "Not now" on Home's restore offer; Settings still offers every backup.
    private(set) var isRestoreOfferDismissed: Bool

    @ObservationIgnored private let settings: BackupSettings
    @ObservationIgnored private let locateStore: () async -> BackupFolderStore?
    @ObservationIgnored private let discoverFolders: () async -> Set<String>
    @ObservationIgnored private let analytics: AnalyticsGateway
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var store: BackupFolderStore?
    @ObservationIgnored private var makeBackup: (() -> DataBackup?)?
    @ObservationIgnored private var pendingBackup: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var runningBackup: Task<Void, Never>?
    @ObservationIgnored private var hasReportedWriteFailure = false
    @ObservationIgnored private var uploadCheck: Task<Void, Never>?
    @ObservationIgnored private var identityObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - locateStore: The backup folder, or nil when iCloud is not available. Called again after the
    ///     iCloud account changes.
    ///   - discoverFolders: Install folders iCloud knows about, including ones not downloaded yet.
    init(
        settings: BackupSettings,
        analytics: AnalyticsGateway,
        debounce: Duration = .seconds(3),
        observesAccountChanges: Bool = false,
        locateStore: @escaping () async -> BackupFolderStore?,
        discoverFolders: @escaping () async -> Set<String> = { [] }
    ) {
        self.settings = settings
        self.analytics = analytics
        self.debounce = debounce
        self.locateStore = locateStore
        self.discoverFolders = discoverFolders
        isEnabled = settings.isEnabled
        lastBackupAt = settings.lastBackupAt
        isRestoreOfferDismissed = settings.isRestoreOfferDismissed
        if observesAccountChanges {
            identityObserver = NotificationCenter.default.addObserver(
                forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.accountChanged() }
            }
        }
    }

    /// The iCloud backup as the app's iCloud container holds it. The folder sits outside the container's
    /// `Documents`, so iCloud Drive and Files never list it.
    static func iCloud(settings: BackupSettings = BackupSettings(), analytics: AnalyticsGateway) -> ICloudBackupService {
        ICloudBackupService(
            settings: settings,
            analytics: analytics,
            observesAccountChanges: true,
            locateStore: {
                await Task.detached(priority: .utility) {
                    // Apple asks for this call off the main thread: it can take a while the first time.
                    guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                        return nil
                    }
                    return BackupFolderStore(
                        root: container.appending(path: "Backups", directoryHint: .isDirectory),
                        usesFileCoordination: true)
                }.value
            },
            discoverFolders: { await ICloudBackupDiscovery.installFolders() })
    }

    /// Connects the journal and makes the first backup of this launch.
    func start(makeBackup: @escaping () -> DataBackup?) async {
        self.makeBackup = makeBackup
        await resolveStore()
        journalChanged()
    }

    // MARK: - Backing up

    /// A change was saved: back up once the changes stop for a moment.
    func journalChanged() {
        guard isEnabled, availability != .unavailable else { return }
        pendingBackup?.cancel()
        pendingBackup = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.backUpNow()
        }
    }

    /// The app is going to the background: write a waiting backup now instead of after the pause.
    func flushPendingBackup() {
        guard let pending = pendingBackup else { return }
        pending.cancel()
        pendingBackup = nil
        let application = UIApplication.shared
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = application.beginBackgroundTask(withName: "iCloud backup") {
            application.endBackgroundTask(taskID)
            taskID = .invalid
        }
        Task {
            await backUpNow()
            if taskID != .invalid { application.endBackgroundTask(taskID) }
        }
    }

    /// Writes the backup now. A call while a write runs waits for it and one more pass, so the backup always
    /// ends up with the journal as it was when the last call came in.
    func backUpNow() async {
        if let running = runningBackup {
            needsAnotherPass = true
            await running.value
            return
        }
        let passes = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.needsAnotherPass = false
                await self.writeBackupOnce()
            } while self.needsAnotherPass
        }
        runningBackup = passes
        await passes.value
        runningBackup = nil
        watchUpload()
    }

    private func writeBackupOnce() async {
        guard isEnabled, let store, let backup = makeBackup?() else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        let writerID = settings.writerID
        let lastHash = settings.lastContentHash
        let outcome: Result<String?, Error> = await Task.detached(priority: .utility) {
            Result {
                let hash = try Self.contentHash(of: backup)
                guard hash != lastHash else { return nil }
                // A fresh install has nothing to protect yet, and must not look like a newer, empty backup.
                if backup.isEmpty && !store.hasBackup(writerID: writerID) { return nil }
                try store.write(backup, writerID: writerID)
                return hash
            }
        }.value
        switch outcome {
        case .success(let hash?):
            settings.lastContentHash = hash
            settings.lastBackupAt = backup.createdAt
            lastBackupAt = backup.createdAt
            lastWriteFailed = false
        case .success(nil):
            lastWriteFailed = false
        case .failure(let error):
            lastWriteFailed = true
            // One report per launch: a full disk would otherwise report after every change.
            if !hasReportedWriteFailure {
                hasReportedWriteFailure = true
                analytics.report(AnalyticsFailure(operation: "write_backup", error: error))
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        settings.isEnabled = enabled
        analytics.track(.iCloudBackupToggled(isOn: enabled))
        if enabled {
            journalChanged()
        } else {
            pendingBackup?.cancel()
            pendingBackup = nil
        }
    }

    /// Checks whether iCloud has the latest backup, a few times while it is still uploading.
    func watchUpload() {
        uploadCheck?.cancel()
        uploadCheck = Task { [weak self] in
            for delay in [0, 5, 20, 60] {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, let self else { return }
                let state = await self.readUploadState()
                self.uploadState = state
                if state != .uploading { return }
            }
        }
    }

    private func readUploadState() async -> BackupUploadState? {
        guard let store, settings.lastBackupAt != nil else { return nil }
        let writerID = settings.writerID
        return await Task.detached(priority: .utility) { store.uploadState(writerID: writerID) }.value
    }

    // MARK: - Restoring

    /// The newest backup from another install, offered on an empty Home.
    var restoreOffer: BackupCandidate? {
        guard !isRestoreOfferDismissed else { return nil }
        return candidates.first { !$0.isThisDevice && ($0.summary.giftsCount > 0 || $0.summary.peopleCount > 0) }
    }

    func dismissRestoreOffer() {
        isRestoreOfferDismissed = true
        settings.isRestoreOfferDismissed = true
    }

    /// Looks for backups in iCloud. After a reinstall iCloud may take a while to list them, so an empty
    /// result is not final; the app looks again when it returns to the foreground.
    func refreshCandidates() async {
        if store == nil { await resolveStore() }
        guard let store, !isLoadingCandidates else { return }
        isLoadingCandidates = true
        let known = await discoverFolders()
        let writerID = settings.writerID
        candidates = await Task.detached(priority: .userInitiated) {
            store.candidates(thisWriterID: writerID, knownFolders: known)
        }.value
        isLoadingCandidates = false
    }

    func loadBackup(_ candidate: BackupCandidate) async throws -> DataBackup {
        guard let store else { throw DataBackupError.unreadable }
        return try await Task.detached(priority: .userInitiated) {
            try store.load(folder: candidate.folderName)
        }.value
    }

    func deleteBackup(_ candidate: BackupCandidate) async throws {
        guard let store else { return }
        try await Task.detached(priority: .userInitiated) {
            try store.delete(folder: candidate.folderName)
        }.value
        candidates.removeAll { $0.id == candidate.id }
        if candidate.isThisDevice {
            // The next change writes a complete backup again.
            settings.lastContentHash = nil
            settings.lastBackupAt = nil
            lastBackupAt = nil
            uploadState = nil
        }
    }

    // MARK: - iCloud account

    private func resolveStore() async {
        let located = await locateStore()
        store = located
        availability = located == nil ? .unavailable : .available
    }

    /// Signing out, or into another account, changes what the container holds: write a full backup again.
    private func accountChanged() {
        settings.lastContentHash = nil
        candidates = []
        uploadState = nil
        availability = .checking
        Task {
            await resolveStore()
            journalChanged()
        }
    }

    /// A hash of what a backup holds, without when or where it was written.
    nonisolated static func contentHash(of backup: DataBackup) throws -> String {
        var content = backup
        content.createdAt = .distantPast
        content.appVersion = ""
        content.deviceModel = ""
        let encoded = try DataBackupCodec.encode(content, photos: .external)
        return SHA256.hash(data: encoded.json).map { String(format: "%02x", $0) }.joined()
    }
}

/// The backup's own preferences, kept apart from the app's: whether it is on, this install's folder and
/// what was last written there.
final class BackupSettings {
    private let defaults: UserDefaults
    private let prefix: String

    /// `prefix` keeps the Debug local-folder backup apart from the real one.
    init(defaults: UserDefaults = .standard, prefix: String = "iCloudBackup.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: prefix + "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "enabled") }
    }

    /// This install's backup folder. UserDefaults go with the app, so a reinstall writes a new folder
    /// and leaves the old one to restore from.
    var writerID: String {
        if let stored = defaults.string(forKey: prefix + "writerID"), UUID(uuidString: stored) != nil {
            return stored
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: prefix + "writerID")
        return id
    }

    var lastBackupAt: Date? {
        get { defaults.object(forKey: prefix + "lastBackupAt") as? Date }
        set { defaults.set(newValue, forKey: prefix + "lastBackupAt") }
    }

    var lastContentHash: String? {
        get { defaults.string(forKey: prefix + "lastContentHash") }
        set { defaults.set(newValue, forKey: prefix + "lastContentHash") }
    }

    var isRestoreOfferDismissed: Bool {
        get { defaults.bool(forKey: prefix + "restoreOfferDismissed") }
        set { defaults.set(newValue, forKey: prefix + "restoreOfferDismissed") }
    }
}

/// Asks iCloud which install folders hold a backup, including ones whose files are not on this device
/// yet; listing the folder alone misses those after a reinstall.
@MainActor
enum ICloudBackupDiscovery {
    static func installFolders(timeout: Duration = .seconds(10)) async -> Set<String> {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, BackupFolderStore.currentFileName)
        return await withCheckedContinuation { continuation in
            var observer: NSObjectProtocol?
            var isFinished = false
            let finish = {
                guard !isFinished else { return }
                isFinished = true
                query.disableUpdates()
                let folders = (query.results as? [NSMetadataItem] ?? []).compactMap { item -> String? in
                    guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { return nil }
                    let folder = url.deletingLastPathComponent()
                    guard folder.deletingLastPathComponent().lastPathComponent == "Backups" else { return nil }
                    return folder.lastPathComponent
                }
                query.stop()
                if let observer { NotificationCenter.default.removeObserver(observer) }
                continuation.resume(returning: Set(folders))
            }
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
            ) { _ in
                MainActor.assumeIsolated { finish() }
            }
            guard query.start() else {
                finish()
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                finish()
            }
        }
    }
}
