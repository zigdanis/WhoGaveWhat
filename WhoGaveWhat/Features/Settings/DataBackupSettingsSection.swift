import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// An exported Who Gave What backup (`.whogavewhat`), declared in Info.plist. It is JSON inside.
    static let whoGaveWhatBackup = UTType(exportedAs: "pro.ziganshin.whogavewhat.backup", conformingTo: .json)
}

/// Settings → Backup: the iCloud backup switch and its status, restoring from iCloud, and exporting or
/// importing all data as a file.
struct DataBackupSettingsSection: View {
    let composition: AppComposition
    @State private var isExporting = false
    @State private var exportedFile: ExportedFile?
    @State private var exportFailed = false
    @State private var isPickingFile = false
    @State private var pendingRestore: PendingRestore?
    @State private var readFailure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: "Backup").padding(.bottom, 7)
            Card {
                VStack(spacing: 0) {
                    if let backup = composition.iCloudBackup {
                        ICloudBackupToggleRow(backup: backup)
                        RowDivider().padding(.leading, 56)
                        NavigationLink {
                            ICloudBackupsView(composition: composition, backup: backup)
                        } label: {
                            SettingsActionRow(
                                icon: "clock.arrow.circlepath", tint: Color.brandFill, label: "Restore from iCloud")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.backup.restore")
                        RowDivider().padding(.leading, 56)
                    }
                    Button(action: export) {
                        SettingsActionRow(
                            icon: "square.and.arrow.up", tint: Color.brandFill, label: "Export all data",
                            isBusy: isExporting)
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .accessibilityIdentifier("settings.backup.export")
                    RowDivider().padding(.leading, 56)
                    Button {
                        isPickingFile = true
                    } label: {
                        SettingsActionRow(
                            icon: "square.and.arrow.down", tint: Color.brandFill, label: "Import from file")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.backup.import")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if let backup = composition.iCloudBackup {
                    Text(verbatim: BackupStatusText.describe(backup))
                        .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("settings.backup.status")
                    SettingsFootnote(text: "settings.backup.footnote")
                } else {
                    SettingsFootnote(text: "settings.backup.export-footnote")
                }
            }
            .padding(.top, 7)
        }
        .task {
            composition.iCloudBackup?.watchUpload()
        }
        .sheet(item: $exportedFile) { file in
            ActivityShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .alert("Couldn't export the data", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data is still saved on this device. Try again in a moment.")
        }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.whoGaveWhatBackup, .json]) { result in
            guard case .success(let url) = result else { return }
            Task { await read(url) }
        }
        .restoreFlow(composition: composition, pending: $pendingRestore, readFailure: $readFailure)
    }

    private func export() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                exportedFile = ExportedFile(url: try await composition.exportBackupFile())
            } catch {
                exportFailed = true
            }
        }
    }

    private func read(_ url: URL) async {
        do {
            pendingRestore = PendingRestore(backup: try await composition.readBackupFile(at: url), source: .file)
        } catch {
            readFailure = RestoreMessages.readFailure(error)
        }
    }
}

/// The iCloud backup switch.
private struct ICloudBackupToggleRow: View {
    let backup: ICloudBackupService

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(name: "icloud.fill", tint: Color.brandFill)
            Toggle(isOn: Binding(get: { backup.isEnabled }, set: { backup.setEnabled($0) })) {
                Text("iCloud backup").font(Font.app(16, .regular)).foregroundColor(Color.textPrimary)
            }
            .tint(Color.brandFill)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .accessibilityIdentifier("settings.backup.icloud")
    }
}

/// The line under the backup card that says whether the data is safe in iCloud.
enum BackupStatusText {
    @MainActor
    static func describe(_ backup: ICloudBackupService) -> String {
        describe(
            isEnabled: backup.isEnabled, availability: backup.availability, isBackingUp: backup.isBackingUp,
            lastBackupAt: backup.lastBackupAt, uploadState: backup.uploadState, lastWriteFailed: backup.lastWriteFailed)
    }

    static func describe(
        isEnabled: Bool,
        availability: ICloudBackupService.Availability,
        isBackingUp: Bool,
        lastBackupAt: Date?,
        uploadState: BackupUploadState?,
        lastWriteFailed: Bool
    ) -> String {
        guard isEnabled else {
            return String(localized: "iCloud backup is off. Your data is only on this device.")
        }
        switch availability {
        case .checking:
            return String(localized: "Checking iCloud…")
        case .unavailable:
            return String(
                localized:
                    "iCloud is not available. To keep a backup, sign in to iCloud in the Settings app and turn on iCloud Drive."
            )
        case .available:
            break
        }
        if lastWriteFailed {
            return String(localized: "Couldn't save the backup. Check that this device has free space.")
        }
        if uploadState == .failed {
            return String(localized: "Couldn't upload the backup. Check that your iCloud storage is not full.")
        }
        if isBackingUp {
            return String(localized: "Backing up…")
        }
        guard let lastBackupAt else {
            return String(localized: "Your data is backed up to iCloud after each change.")
        }
        let time = lastBackupAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
        if uploadState == .uploading {
            return String(localized: "Last backup \(time). Uploading to iCloud…", comment: "Relative time, e.g. 2 minutes ago.")
        }
        return String(localized: "Last backup \(time).", comment: "Relative time, e.g. 2 minutes ago.")
    }
}
