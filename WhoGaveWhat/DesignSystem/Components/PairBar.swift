import SwiftUI

/// Two-segment proportion bar. The segments share the width by value and stay
/// apart with a small gap; both empty leaves the bare track.
struct PairBar: View {
    let first: Double
    let second: Double
    let firstColor: Color
    let secondColor: Color
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let total = max(first, 0) + max(second, 0)
            let firstWidth = total > 0 ? geometry.size.width * CGFloat(max(first, 0) / total) : 0
            HStack(spacing: 2) {
                if total > 0 {
                    if first > 0 { Rectangle().fill(firstColor).frame(width: max(firstWidth, height)) }
                    if second > 0 { Rectangle().fill(secondColor) }
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
        }
        .frame(height: height)
        .background(Color.fillTrack)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
