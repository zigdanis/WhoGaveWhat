import SwiftUI

/// Grouped surface used for lists of rows and summary blocks.
struct Card<Content: View>: View {
    var corner: CGFloat = DesignMetrics.radiusLarge
    var lifted = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                Color.surface,
                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .modifier(OptionalLift(on: lifted))
    }
}

private struct OptionalLift: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.softShadow(prominent: true) } else { content }
    }
}
