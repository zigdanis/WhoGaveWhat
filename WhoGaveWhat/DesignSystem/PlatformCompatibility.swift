import SwiftUI

// The app supports iOS 18.4 and later. Each iOS 26-only API sits behind exactly one
// `#available` check in this file; feature code calls these modifiers instead.
// On iOS 26 and later every modifier applies the same API the call sites used before.

extension View {
    /// `.glassProminent` on iOS 26+; `.borderedProminent` on iOS 18.
    @ViewBuilder
    func prominentGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// `.glass` on iOS 26+; `.bordered` on iOS 18.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Interactive Liquid Glass in `shape` on iOS 26+; a regular-material `shape`
    /// filled with `tint` (when set) on iOS 18.
    @ViewBuilder
    func glassSurface(in shape: some Shape, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background {
                shape.fill(.regularMaterial)
                if let tint { shape.fill(tint) }
            }
        }
    }

    /// Soft bottom scroll-edge effect on iOS 26+; no-op on iOS 18.
    @ViewBuilder
    func softBottomScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
    }

    /// Tab bar that minimizes on scroll down on iOS 26+; no-op on iOS 18.
    @ViewBuilder
    func minimizingTabBar() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Zero horizontal list section margins on iOS 26+; no-op on iOS 18.
    @ViewBuilder
    func zeroHorizontalListSectionMargins() -> some View {
        if #available(iOS 26.0, *) {
            listSectionMargins(.horizontal, 0)
        } else {
            self
        }
    }
}
