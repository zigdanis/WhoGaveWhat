import Foundation
import UIKit

enum DataRestoreResult: Equatable {
    case restored(DataRestoreSummary)
    /// Nothing was added: the store refused the records, or the journal could not be loaded first.
    case failed
}

/// The journal could not be read for an export.
struct DataExportError: Error {}

extension AppComposition {
    /// The iCloud backup for a real launch. Verification launches never write to the user's iCloud; in
    /// Debug, `KS_BACKUP=local` (or `-KS_BACKUP local`) backs up to a folder on the device instead, so the
    /// backup screens can be walked on a simulator without an iCloud account.
    static func makeICloudBackup(
        environment: [String: String], arguments: [String], analytics: AnalyticsGateway
    ) -> ICloudBackupService? {
        #if DEBUG
            if LaunchFlags.value("KS_BACKUP", environment: environment, arguments: arguments) == "local" {
                return LaunchFlags.localBackup(environment: environment, arguments: arguments, analytics: analytics)
            }
        #endif
        guard !MonitoringConfiguration.isVerificationLaunch(environment, arguments: arguments) else { return nil }
        return .iCloud(analytics: analytics)
    }

    func startICloudBackup() {
        guard let iCloudBackup else { return }
        Task { [weak self] in
            await iCloudBackup.start { [weak self] in self?.makeBackup() }
            self?.lookForBackupToRestore()
        }
    }

    /// An empty journal may be a reinstall: look for a backup to offer on Home.
    func lookForBackupToRestore() {
        guard let iCloudBackup, data.isJournalEmpty, iCloudBackup.isEnabled else { return }
        Task { await iCloudBackup.refreshCandidates() }
    }

    /// The whole journal as stored, with the preferences that refer to it. Nil before the journal has
    /// loaded or while loading fails, since the records on screen may then be out of date.
    func makeBackup(createdAt: Date = Date()) -> DataBackup? {
        guard let journalArchive, data.hasLoadedSnapshot, !data.isLoadFailing else { return nil }
        do {
            let archive = try journalArchive.loadArchive()
            return DataBackup(
                createdAt: createdAt,
                appVersion: Self.appVersion,
                deviceModel: UIDevice.current.model,
                defaultCurrency: defaultCurrency,
                selfPersonID: data.selfPersonID,
                people: archive.people,
                gifts: archive.gifts)
        } catch {
            analytics.report(AnalyticsFailure(operation: "read_backup", error: error))
            return nil
        }
    }

    /// Adds the backup's records that the journal lacks; nothing already here is changed or deleted. Into an
    /// empty journal it also brings back the default currency and "This is me".
    @discardableResult
    func restore(_ backup: DataBackup, source: DataRestoreSource) -> DataRestoreResult {
        // Restoring next to records that could not be reloaded would match them against an old snapshot.
        guard let journalArchive, refreshStaleSnapshot() else {
            haptics.play(.error)
            return .failed
        }
        let summary: DataRestoreSummary
        do {
            summary = try journalArchive.restore(backup)
        } catch {
            analytics.report(
                AnalyticsFailure(operation: "restore_backup", error: error, details: ["source": .string(source.rawValue)]))
            haptics.play(.error)
            reloadData()
            return .failed
        }
        if summary.restoredIntoEmptyJournal {
            applyRestoredPreferences(currency: backup.defaultCurrency, selfPersonID: summary.restoredSelfPersonID)
        }
        reloadData()
        analytics.track(
            .dataRestored(
                source: source, peopleAdded: summary.peopleAdded, giftsAdded: summary.giftsAdded,
                intoEmptyJournal: summary.restoredIntoEmptyJournal))
        haptics.play(summary.addedAnything ? .success : .softImpact)
        return .restored(summary)
    }

    /// Writes every record, photo and preference to one `.whogavewhat` file for the share sheet.
    func exportBackupFile(now: Date = Date()) async throws -> URL {
        guard let backup = makeBackup(createdAt: now) else { throw DataExportError() }
        let folder = FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        let url = folder.appending(path: Self.exportFileName(for: now))
        do {
            try await Task.detached(priority: .userInitiated) {
                // Only the latest export stays on the device.
                try? FileManager.default.removeItem(at: folder)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let json = try DataBackupCodec.encode(backup, photos: .inline).json
                // Import would refuse it, so a file this large would be a backup that cannot be restored.
                guard json.count <= DataBackupCodec.maximumFileSize else { throw CocoaError(.fileWriteOutOfSpace) }
                try json.write(to: url, options: .atomic)
            }.value
        } catch {
            analytics.report(AnalyticsFailure(operation: "export_data", error: error))
            throw error
        }
        analytics.track(.dataExported(peopleCount: backup.people.count, giftsCount: backup.gifts.count))
        return url
    }

    /// Reads a file the user picked, e.g. from Files or iCloud Drive, downloading it first if needed.
    func readBackupFile(at url: URL) async throws -> DataBackup {
        try await Task.detached(priority: .userInitiated) {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            var coordinationError: NSError?
            var result: Result<Data, Error> = .failure(DataBackupError.unreadable)
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
                result = Result {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    // Far beyond any real journal; export refuses to write a larger file.
                    guard size <= DataBackupCodec.maximumFileSize else { throw DataBackupError.unreadable }
                    return try Data(contentsOf: url)
                }
            }
            if let coordinationError { throw coordinationError }
            return try DataBackupCodec.decode(try result.get())
        }.value
    }

    nonisolated static func exportFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "WhoGaveWhat-\(formatter.string(from: date)).\(DataBackupCodec.fileExtension)"
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
