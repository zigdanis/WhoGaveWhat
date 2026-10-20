import SwiftUI

/// A trailing trash swipe action that confirms with a system dialog.
///
/// The dialog is attached to the row itself, not the surrounding `List`: on iOS 26 a
/// `confirmationDialog` is a popover anchored to the view that carries the modifier, so a
/// list-level dialog would point at the whole list instead of the swiped row. Each row owns
/// its own `confirming` state for the same reason.
///
/// The trash button sets an explicit red tint because swipe-action buttons inherit the
/// app-wide brand tint, which would otherwise colour the destructive action green.
private struct SwipeToDeleteConfirmation: ViewModifier {
    let title: Text
    let confirmLabel: Text
    let message: Text?
    let allowsFullSwipe: Bool
    let isEnabled: Bool
    let onConfirm: () -> Void
    @State private var confirming = false

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
                if isEnabled {
                    Button(role: .destructive) {
                        confirming = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete")
                    .tint(Color.destructive)
                }
            }
            .confirmationDialog(title, isPresented: $confirming, titleVisibility: .visible) {
                Button(role: .destructive, action: onConfirm) {
                    confirmLabel
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let message {
                    message
                }
            }
    }
}

extension View {
    /// Adds a red trailing trash swipe that asks for confirmation next to the row before `onConfirm` runs.
    func swipeToDelete(
        title: Text,
        confirmLabel: Text = Text("Delete"),
        message: Text? = nil,
        allowsFullSwipe: Bool,
        isEnabled: Bool = true,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            SwipeToDeleteConfirmation(
                title: title,
                confirmLabel: confirmLabel,
                message: message,
                allowsFullSwipe: allowsFullSwipe,
                isEnabled: isEnabled,
                onConfirm: onConfirm))
    }
}
