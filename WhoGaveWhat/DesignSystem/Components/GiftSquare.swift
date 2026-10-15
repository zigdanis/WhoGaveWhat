import SwiftUI

/// Rounded-square tile for a gift's emoji. Gifts are squircles; people are circles.
struct GiftSquare: View {
    let emoji: String
    let tint: Color
    var size: CGFloat = 44
    var corner: CGFloat = DesignMetrics.radiusSmall
    var fontSize: CGFloat = 23

    var body: some View {
        Text(emoji)
            .font(.system(size: fontSize))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(tint))
    }
}
