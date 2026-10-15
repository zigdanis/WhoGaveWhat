import SwiftUI

/// Floating primary action rendered as a prominent Liquid Glass capsule, pinned
/// just above the tab bar by `floatingAddButton` and the People screen.
struct FloatingActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Font.app(16, .semibold))
                .padding(.horizontal, 6)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.brandFill)
        .padding(.bottom, 6)
    }
}
