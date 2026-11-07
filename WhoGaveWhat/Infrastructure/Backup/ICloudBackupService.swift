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
    /// The iCloud account's `ubiquityIdentityToken`, nil without one or in tests.
    @ObservationIgnored private let accountIdentity: () -> NSObject?
    @ObservationIgnored private let analytics: AnalyticsGateway
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var store: BackupFolderStore?
    @ObservationIgnored private var makeBackup: (() -> DataBackup?)?
    @ObservationIgnored private var pendingBackup: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var runningBackup: Task<Void, Never>?
    /// Changes with the iCloud account, so a write that started for the previous account cannot mark the
    /// new one as backed up.
    @ObservationIgnored private var storeGeneration = 0
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
        discoverFolders: @escaping () async -> Set<String> = { [] },
        accountIdentity: @escaping () -> NSObject? = { nil }
    ) {
        self.settings = settings
        self.analytics = analytics
        self.debounce = debounce
        self.locateStore = locateStore
        self.discoverFolders = discoverFolders
        self.accountIdentity = accountIdentity
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
    static func iCloud(settings: BackupSettings? = nil, analytics: AnalyticsGateway) -> ICloudBackupService {
        ICloudBackupService(
            settings: settings ?? BackupSettings(deviceID: UIDevice.current.identifierForVendor?.uuidString),
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
            discoverFolders: { await ICloudBackupDiscovery.installFolders() },
            accountIdentity: { FileManager.default.ubiquityIdentityToken as? NSObject })
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
        // A call that came in after the last pass decided to stop, but before this point, joined a finished
        // task; it still needs its pass.
        if needsAnotherPass {
            await backUpNow()
            return
        }
        watchUpload()
    }

    private func writeBackupOnce() async {
        guard isEnabled, let store, let backup = makeBackup?() else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        let writerID = settings.writerID
        let lastHash = settings.lastContentHash
        let generation = storeGeneration
        let outcome: Result<WriteOutcome, Error> = await Task.detached(priority: .utility) {
            Result {
                let hash = try Self.contentHash(of: backup)
                let exists = store.hasBackup(writerID: writerID)
                // Unchanged content needs no write, unless the backup has gone (e.g. deleted from another
                // device) or is damaged or missing a photo: then the journal here writes it again.
                if hash == lastHash && exists && store.isIntact(writerID: writerID) { return .unchanged }
                // A fresh install has nothing to protect yet, and must not look like a newer, empty backup.
                if backup.isEmpty && !exists { return .skipped }
                try store.write(backup, writerID: writerID)
                return .written(hash)
            }
        }.value
        guard generation == storeGeneration else { return }
        switch outcome {
        case .success(.written(let hash)):
            settings.lastContentHash = hash
            settings.lastBackupAt = backup.createdAt
            lastBackupAt = backup.createdAt
            lastWriteFailed = false
        case .success(.skipped):
            // Nothing in iCloud for this install: no "Last backup" to show.
            settings.lastContentHash = nil
            settings.lastBackupAt = nil
            lastBackupAt = nil
            lastWriteFailed = false
        case .success(.unchanged):
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
                let generation = self.storeGeneration
                let state = await self.readUploadState()
                // A read for the previous iCloud account must not replace the new account's state.
                guard !Task.isCancelled, generation == self.storeGeneration else { return }
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
        // An earlier copy stays in Settings: its install emptied the journal on purpose.
        return candidates.first { !$0.isThisDevice && !$0.isPreviousCopy && !$0.summary.isEmpty }
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
        let generation = storeGeneration
        let known = await discoverFolders()
        let writerID = settings.writerID
        let found = await Task.detached(priority: .userInitiated) {
            store.candidates(thisWriterID: writerID, knownFolders: known)
        }.value
        isLoadingCandidates = false
        // The iCloud account changed meanwhile: these are the previous account's backups; look again.
        guard generation == storeGeneration else {
            await refreshCandidates()
            return
        }
        candidates = found
    }

    /// Loads a backup with its photos. When the latest copy cannot be loaded, its complete previous copy
    /// joins the list, so the user can restore that instead.
    func loadBackup(_ candidate: BackupCandidate) async throws -> DataBackup {
        guard let store else { throw DataBackupError.unreadable }
        let writerID = settings.writerID
        let result = await Task.detached(priority: .userInitiated) {
            Result { try store.load(folder: candidate.folderName, previousCopy: candidate.isPreviousCopy) }
        }.value
        if case .failure = result, !candidate.isPreviousCopy,
            !candidates.contains(where: { $0.folderName == candidate.folderName && $0.isPreviousCopy }),
            let earlier = await Task.detached(
                priority: .userInitiated,
                operation: {
                    store.previousCandidate(folder: candidate.folderName, thisWriterID: writerID)
                }
            ).value
        {
            candidates.append(earlier)
            candidates.sort { $0.summary.createdAt > $1.summary.createdAt }
        }
        return try result.get()
    }

    func deleteBackup(_ candidate: BackupCandidate) async throws {
        guard let store else { return }
        try await Task.detached(priority: .userInitiated) {
            try store.delete(folder: candidate.folderName, previousCopyOnly: candidate.isPreviousCopy)
        }.value
        candidates.removeAll { $0.folderName == candidate.folderName && (candidate.isPreviousCopy ? $0.isPreviousCopy : true) }
        if candidate.isThisDevice && !candidate.isPreviousCopy {
            // The next change writes a complete backup again.
            settings.lastContentHash = nil
            settings.lastBackupAt = nil
            lastBackupAt = nil
            uploadState = nil
        }
    }

    // MARK: - iCloud account

    private func resolveStore() async {
        let generation = storeGeneration
        let located = await locateStore()
        // An account change while locating started a newer lookup; this result is for the previous account.
        guard generation == storeGeneration else { return }
        noteAccountIdentity()
        store = located
        availability = located == nil ? .unavailable : .available
    }

    /// The account can change while the app is not running: a write remembered for another account must
    /// not let this one skip its backup.
    private func noteAccountIdentity() {
        guard let identity = accountIdentity(),
            let archived = try? NSKeyedArchiver.archivedData(withRootObject: identity, requiringSecureCoding: true)
        else { return }
        defer { settings.accountIdentity = archived }
        guard let stored = settings.accountIdentity, stored != archived else { return }
        // Apple compares tokens with isEqual; differing archives of an equal token change nothing.
        if let previous = (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSObject.self], from: stored)) as? NSObject,
            previous.isEqual(identity)
        {
            return
        }
        settings.lastContentHash = nil
        settings.lastBackupAt = nil
        lastBackupAt = nil
    }

    /// Signing out, or into another account, changes what the container holds: write a full backup again.
    private func accountChanged() {
        storeGeneration += 1
        // Nothing reads or writes the previous account's folder while the new one is located; a write
        // already running finishes there and its result is discarded (see `storeGeneration`).
        store = nil
        pendingBackup?.cancel()
        pendingBackup = nil
        settings.lastContentHash = nil
        settings.lastBackupAt = nil
        lastBackupAt = nil
        candidates = []
        uploadState = nil
        availability = .checking
        Task {
            await resolveStore()
            journalChanged()
        }
    }

    private enum WriteOutcome: Sendable {
        case written(String)
        case unchanged
        case skipped
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

    /// - Parameters:
    ///   - prefix: Keeps the Debug local-folder backup apart from the real one.
    ///   - deviceID: This device's `identifierForVendor`. UserDefaults move to a new iPhone with Quick Start
    ///     or a device backup, and two phones in use must not share one backup folder, so a different
    ///     device starts its own folder. Nil (not known yet, e.g. before the first unlock) changes nothing.
    init(defaults: UserDefaults = .standard, prefix: String = "iCloudBackup.", deviceID: String? = nil) {
        self.defaults = defaults
        self.prefix = prefix
        guard let deviceID else { return }
        let deviceKey = prefix + "writerDevice"
        if let stored = defaults.string(forKey: deviceKey), stored != deviceID {
            for key in ["writerID", "lastContentHash", "lastBackupAt"] {
                defaults.removeObject(forKey: prefix + key)
            }
        }
        defaults.set(deviceID, forKey: deviceKey)
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: prefix + "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefix + "enabled") }
    }

    /// This install's backup folder. UserDefaults go with the app, so a reinstall writes a new folder
    /// and leaves the old one to restore from; a Keychain item would survive deleting the app and must not
    /// be used. A move to another device also gets a new folder (see `init`).
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

    /// The archived `ubiquityIdentityToken` the last backup was written for.
    var accountIdentity: Data? {
        get { defaults.data(forKey: prefix + "accountIdentity") }
        set { defaults.set(newValue, forKey: prefix + "accountIdentity") }
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
