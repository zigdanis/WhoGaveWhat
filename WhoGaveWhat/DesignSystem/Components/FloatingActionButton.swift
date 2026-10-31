import SwiftUI

/// Floating primary action rendered as a prominent Liquid Glass capsule, pinned
/// just above the tab bar by `floatingAddButton` and the People screen.
struct FloatingActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    @Environment(\.haptics) private var haptics

    var body: some View {
        Button {
            haptics.play(.softImpact)
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(Font.app(16, .semibold))
                .foregroundStyle(Color.onFill)
                .lineLimit(1)
                .padding(.horizontal, 6)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.brandFill)
        .padding(.bottom, 6)
    }
}
