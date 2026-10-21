import SwiftUI

enum CompactVerticalSpace {
    /// Regular iPhones have at least 760 pt of safe height; iPhone Duo's outer display about 634
    /// and iPhone SE about 647.
    static let maxHeight: CGFloat = 720

    static func isCompact(safeHeight: CGFloat) -> Bool {
        safeHeight > 0 && safeHeight < maxHeight
    }
}

extension EnvironmentValues {
    /// Whether the window is short, like iPhone Duo's outer display. Forms tighten their vertical
    /// spacing there so their actions still fit above the keyboard.
    @Entry var compactVerticalSpace: Bool = false
}

extension View {
    /// Publishes `compactVerticalSpace` from this root view's safe height, keyboard excluded,
    /// to everything below it, including sheets.
    func measuresCompactVerticalSpace() -> some View {
        modifier(CompactVerticalSpaceReader())
    }
}

private struct CompactVerticalSpaceReader: ViewModifier {
    @State private var isCompact = false

    func body(content: Content) -> some View {
        content
            .background {
                // Ignoring the keyboard keeps the value steady while someone types.
                Color.clear
                    .ignoresSafeArea(.keyboard)
                    .onGeometryChange(for: Bool.self) { proxy in
                        CompactVerticalSpace.isCompact(safeHeight: proxy.size.height)
                    } action: { compact in
                        isCompact = compact
                    }
            }
            .environment(\.compactVerticalSpace, isCompact)
    }
}
