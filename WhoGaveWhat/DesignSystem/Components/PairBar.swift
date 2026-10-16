import SwiftUI

/// Width math for `PairBar`, kept free of views so it can be tested.
enum PairBarLayout {
    /// Segment widths for two values sharing `available` width. The segments split
    /// the width left after the `gap` in proportion to the values, each non-empty segment
    /// keeps at least `minimum`, and gap plus segments never exceed `available`.
    static func widths(
        first: Double,
        second: Double,
        available: CGFloat,
        gap: CGFloat,
        minimum: CGFloat
    ) -> (first: CGFloat, second: CGFloat) {
        let firstValue = max(first, 0)
        let secondValue = max(second, 0)
        let total = firstValue + secondValue
        guard total > 0, available > 0 else { return (0, 0) }
        if secondValue == 0 { return (available, 0) }
        if firstValue == 0 { return (0, available) }

        let usable = max(available - gap, 0)
        let floor = min(minimum, usable / 2)
        var firstWidth = max(usable * CGFloat(firstValue / total), floor)
        var secondWidth = max(usable * CGFloat(secondValue / total), floor)
        if firstWidth + secondWidth > usable {
            if firstWidth > secondWidth {
                firstWidth = usable - secondWidth
            } else {
                secondWidth = usable - firstWidth
            }
        }
        return (firstWidth, secondWidth)
    }
}

/// Two-segment proportion bar. The segments share the width by value and stay
/// apart with a small gap; both empty leaves the bare track.
struct PairBar: View {
    let first: Double
    let second: Double
    let firstColor: Color
    let secondColor: Color
    var height: CGFloat = 12

    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let widths = PairBarLayout.widths(
                first: first, second: second, available: geometry.size.width, gap: gap, minimum: 4)
            HStack(spacing: gap) {
                if widths.first > 0 { Rectangle().fill(firstColor).frame(width: widths.first) }
                if widths.second > 0 { Rectangle().fill(secondColor).frame(width: widths.second) }
            }
            .frame(width: geometry.size.width, alignment: .leading)
        }
        .frame(height: height)
        .background(Color.fillTrack)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
