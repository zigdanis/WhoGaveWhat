import SwiftUI

/// A backup the user picked, waiting for them to confirm the restore.
struct PendingRestore: Identifiable {
    let id = UUID()
    let backup: DataBackup
    let source: DataRestoreSource
}

/// The texts of a restore, shared by Home's offer, the iCloud backups list and file import.
enum RestoreMessages {
    /// "Gifts: 12 · People: 10", which reads well in both languages without plural forms.
    static func contents(giftsCount: Int, peopleCount: Int) -> String {
        String(localized: "Gifts: \(giftsCount) · People: \(peopleCount)", comment: "What a backup holds.")
    }

    static func confirmation(for backup: DataBackup) -> String {
        let date = backup.createdAt.formatted(date: .long, time: .shortened)
        let contents = contents(giftsCount: backup.gifts.count, peopleCount: backup.people.count)
        return String(
            localized:
                "Saved \(date). \(contents).\n\nOnly what is missing is added. Nothing in the app is changed or deleted.",
            comment: "Before restoring a backup: when it was saved and what it holds.")
    }

    static func outcome(_ summary: DataRestoreSummary) -> String {
        guard summary.addedAnything else {
            return String(localized: "Everything in this backup is already in the app.")
        }
        return String(
            localized: "Gifts added: \(summary.giftsAdded). People added: \(summary.peopleAdded).",
            comment: "After a restore: how many records were added.")
    }

    /// Why a backup could not be opened.
    static func readFailure(_ error: Error) -> String {
        switch error as? DataBackupError {
        case .newerVersion:
            String(localized: "This backup was made by a newer version of the app. Update Who Gave What and try again.")
        case .unreadable, .inconsistent:
            String(localized: "This file is not a Who Gave What backup, or it is damaged.")
        case nil:
            String(localized: "Couldn't read the backup. Check your internet connection and try again.")
        }
    }
}

/// Confirms a picked backup, restores it and says what was added.
private struct RestoreFlow: ViewModifier {
    let composition: AppComposition
    @Binding var pending: PendingRestore?
    @Binding var readFailure: String?
    @State private var outcome: DataRestoreResult?

    func body(content: Content) -> some View {
        content
            .alert(
                "Restore this backup?", isPresented: isPresented($pending), presenting: pending
            ) { request in
                Button("Restore") {
                    outcome = composition.restore(request.backup, source: request.source)
                }
                .accessibilityIdentifier("backup.restore.confirm")
                Button("Cancel", role: .cancel) {}
            } message: { request in
                Text(verbatim: RestoreMessages.confirmation(for: request.backup))
            }
            .alert(outcomeTitle, isPresented: isPresented($outcome), presenting: outcome) { _ in
                Button("OK", role: .cancel) {}
            } message: { outcome in
                switch outcome {
                case .restored(let summary): Text(verbatim: RestoreMessages.outcome(summary))
                case .failed: Text("Nothing was changed. Try again.")
                }
            }
            .alert("Couldn't open the backup", isPresented: isPresented($readFailure), presenting: readFailure) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(verbatim: message)
            }
    }

    private var outcomeTitle: LocalizedStringKey {
        if case .failed = outcome { return "Couldn't restore the backup" }
        return "Backup restored"
    }

    private func isPresented<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}

extension View {
    func restoreFlow(
        composition: AppComposition, pending: Binding<PendingRestore?>, readFailure: Binding<String?>
    ) -> some View {
        modifier(RestoreFlow(composition: composition, pending: pending, readFailure: readFailure))
    }
}

/// The system share sheet for an exported file: AirDrop, Mail, Save to Files and so on.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// An export ready to share.
struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
