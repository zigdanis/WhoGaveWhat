import SwiftUI

/// Grouped surface used for lists of rows and summary blocks.
struct Card<Content: View>: View {
    var corner: CGFloat = DesignMetrics.radiusLarge
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                Color.surface,
                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
