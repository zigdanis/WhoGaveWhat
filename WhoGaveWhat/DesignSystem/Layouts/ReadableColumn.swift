import SwiftUI

enum ReadableWidth {
    static let content: CGFloat = 560
    static let onboarding: CGFloat = 480
}

/// Side margin that centers a column of at most `maxWidth` in a container of `containerWidth`.
func readableMargin(containerWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
    max(0, (containerWidth - maxWidth) / 2)
}

private struct ReadableColumn: ViewModifier {
    let maxWidth: CGFloat
    @State private var containerWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // Safe-area padding adds to the list's own margins, so a zero margin changes nothing;
            // content margins would replace an inset-grouped list's default side margins.
            .safeAreaPadding(.horizontal, readableMargin(containerWidth: containerWidth, maxWidth: maxWidth))
            // Measured outside the padding, so the margin can never feed back into the width.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                containerWidth = width
            }
    }
}

extension View {
    /// Keeps a scroll container's content at a readable width, centered, when the window is wide.
    /// Compact widths get a zero margin, so iPhones look unchanged.
    func readableColumn(maxWidth: CGFloat = ReadableWidth.content) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth))
    }
}
