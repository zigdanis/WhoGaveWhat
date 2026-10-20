import SwiftUI

/// Signed gift-count chip: received tint when ahead, given tint when behind, and a friendly
/// brand-tinted "Even" at zero.
struct CountBalanceBadge: View {
    let net: Int

    var body: some View {
        label
            .font(Font.app(14, .semibold, rounded: true))
            .foregroundColor(foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint))
            .fixedSize()
    }

    private var label: Text {
        net == 0
            ? Text("Even 🤝")
            : Text(verbatim: formattedSignedCount(net))
    }

    private var foreground: Color {
        net == 0 ? Color.brand : appearance.main
    }

    private var tint: Color {
        net == 0 ? Color.brand.opacity(0.12) : appearance.tint
    }

    private var appearance: GiftDirectionAppearance {
        (net > 0 ? GiftDirection.received : GiftDirection.given).appearance
    }
}
