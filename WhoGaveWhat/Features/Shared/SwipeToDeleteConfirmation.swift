import SwiftUI

/// A trailing trash swipe action that confirms with a system dialog. When the deletion fails the row stays
/// and an alert says so.
///
/// The dialog is attached to the row itself, not the surrounding `List`: on iOS 26 a
/// `confirmationDialog` is a popover anchored to the view that carries the modifier, so a
/// list-level dialog would point at the whole list instead of the swiped row. Each row owns
/// its own `confirming` state for the same reason.
///
/// The trash button sets an explicit red tint because swipe-action buttons inherit the
/// app-wide brand tint, which would otherwise colour it green. It has no `.destructive`
/// role: in a `List` that role starts the row-removal animation on tap, before the user
/// has confirmed, and this row is the dialog's anchor.
private struct SwipeToDeleteConfirmation: ViewModifier {
    let title: Text
    let confirmLabel: Text
    let message: Text?
    let allowsFullSwipe: Bool
    let isEnabled: Bool
    let failureTitle: Text
    let onConfirm: () -> DeletionResult
    @State private var confirming = false
    @State private var failed = false

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
                if isEnabled {
                    Button {
                        confirming = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete")
                    .tint(Color.destructive)
                }
            }
            .confirmationDialog(title, isPresented: $confirming, titleVisibility: .visible) {
                Button(role: .destructive) {
                    failed = onConfirm() == .failed
                } label: {
                    confirmLabel
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let message {
                    message
                }
            }
            .alert(failureTitle, isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing was deleted. Try again.")
            }
    }
}

extension View {
    /// Adds a red trailing trash swipe that asks for confirmation next to the row before `onConfirm` runs,
    /// and shows `failureTitle` when `onConfirm` reports that nothing was deleted.
    func swipeToDelete(
        title: Text,
        confirmLabel: Text = Text("Delete"),
        message: Text? = nil,
        allowsFullSwipe: Bool,
        isEnabled: Bool = true,
        failureTitle: Text,
        onConfirm: @escaping () -> DeletionResult
    ) -> some View {
        modifier(
            SwipeToDeleteConfirmation(
                title: title,
                confirmLabel: confirmLabel,
                message: message,
                allowsFullSwipe: allowsFullSwipe,
                isEnabled: isEnabled,
                failureTitle: failureTitle,
                onConfirm: onConfirm))
    }
}
