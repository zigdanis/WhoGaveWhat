#if DEBUG
    import Foundation

    /// Debug-only switches for verification launches. Each `KS_` flag is read from the environment or, for a
    /// launcher that cannot set it, from launch arguments (`-KS_BACKUP local`). Release builds compile none
    /// of this, and like every `KS_` launch these keep monitoring off.
    enum LaunchFlags {
        static func value(
            _ name: String,
            environment: [String: String] = ProcessInfo.processInfo.environment,
            arguments: [String] = ProcessInfo.processInfo.arguments
        ) -> String? {
            if let value = environment[name] { return value }
            guard let index = arguments.firstIndex(of: "-" + name), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        /// `KS_EMPTY_STORE=1` opens an empty in-memory journal, like a fresh install, leaving the data on
        /// the device untouched.
        static var opensEmptyStore: Bool {
            value("KS_EMPTY_STORE") == "1"
        }

        /// `KS_BACKUP=local`: the backup writes to `Application Support/DebugBackups` instead of iCloud.
        /// With `KS_EMPTY_STORE=1` every launch also gets a new install folder, so backups written by
        /// earlier launches appear as another device's, ready to restore.
        @MainActor
        static func localBackup(
            environment: [String: String], arguments: [String], analytics: AnalyticsGateway
        ) -> ICloudBackupService {
            let settings: BackupSettings
            if value("KS_EMPTY_STORE", environment: environment, arguments: arguments) == "1" {
                let suite = "pro.ziganshin.WhoGaveWhat.debug-backup-fresh-install"
                let defaults = UserDefaults(suiteName: suite) ?? .standard
                defaults.removePersistentDomain(forName: suite)
                settings = BackupSettings(defaults: defaults, prefix: "debugBackup.")
            } else {
                settings = BackupSettings(prefix: "debugBackup.")
            }
            return ICloudBackupService(
                settings: settings,
                analytics: analytics,
                locateStore: {
                    let support = URL.applicationSupportDirectory
                    return BackupFolderStore(
                        root: support.appending(path: "DebugBackups", directoryHint: .isDirectory),
                        usesFileCoordination: false)
                })
        }
    }
#endif
