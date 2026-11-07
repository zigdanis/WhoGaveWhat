import SwiftUI

/// Settings → Restore from iCloud: every backup in the user's iCloud, newest first, one per install of the
/// app. Tapping one restores it after a confirmation; swiping deletes it from iCloud. This list is the only
/// place a single backup can be seen or removed, since iCloud Drive does not show them.
struct ICloudBackupsView: View {
    let composition: AppComposition
    let backup: ICloudBackupService
    @State private var loadingID: String?
    @State private var pendingRestore: PendingRestore?
    @State private var readFailure: String?
    @State private var deletion: BackupCandidate?
    @State private var deletionFailed = false

    var body: some View {
        List {
            if backup.availability == .unavailable {
                Section {
                    Text(
                        "iCloud is not available. To keep a backup, sign in to iCloud in the Settings app and turn on iCloud Drive."
                    )
                    .font(Font.app(15, .regular)).foregroundColor(Color.textSecondary)
                }
            } else if backup.candidates.isEmpty {
                Section {
                    if backup.isLoadingCandidates || backup.availability == .checking {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking for backups…").foregroundColor(Color.textSecondary)
                        }
                    } else {
                        Text("No backups in iCloud yet.").foregroundColor(Color.textSecondary)
                    }
                }
            } else {
                Section {
                    ForEach(backup.candidates) { candidate in
                        row(candidate)
                    }
                } footer: {
                    Text("Restoring adds only what is missing. Nothing in the app is changed or deleted.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .readableColumn()
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("iCloud backups")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("backup.list")
        .task { await backup.refreshCandidates() }
        .refreshable { await backup.refreshCandidates() }
        .restoreFlow(composition: composition, pending: $pendingRestore, readFailure: $readFailure)
        .confirmationDialog(
            "Delete this backup from iCloud?", isPresented: isDeleting, titleVisibility: .visible, presenting: deletion
        ) { candidate in
            Button("Delete Backup", role: .destructive) {
                Task { await delete(candidate) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your gifts and people in the app stay as they are.")
        }
        .alert("Couldn't delete the backup", isPresented: $deletionFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again in a moment.")
        }
    }

    private func row(_ candidate: BackupCandidate) -> some View {
        Button {
            Task { await load(candidate) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: candidate.summary.deviceModel == "iPad" ? "ipad" : "iphone")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color.brand)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: candidate.summary.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Font.app(16, .regular)).foregroundColor(Color.textPrimary)
                    Text(verbatim: subtitle(candidate))
                        .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
                }
                Spacer(minLength: 8)
                if loadingID == candidate.id {
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loadingID != nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                deletion = candidate
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
            .tint(Color.destructive)
        }
        .accessibilityIdentifier("backup.candidate")
    }

    private func subtitle(_ candidate: BackupCandidate) -> String {
        let contents = RestoreMessages.contents(
            giftsCount: candidate.summary.giftsCount, peopleCount: candidate.summary.peopleCount)
        let device =
            candidate.isThisDevice
            ? String(localized: "This device") : candidate.summary.deviceModel
        return device.isEmpty ? contents : "\(device) · \(contents)"
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })
    }

    private func load(_ candidate: BackupCandidate) async {
        loadingID = candidate.id
        defer { loadingID = nil }
        do {
            pendingRestore = PendingRestore(backup: try await backup.loadBackup(candidate), source: .iCloud)
        } catch {
            readFailure = RestoreMessages.readFailure(error)
        }
    }

    private func delete(_ candidate: BackupCandidate) async {
        do {
            try await backup.deleteBackup(candidate)
        } catch {
            deletionFailed = true
        }
    }
}
