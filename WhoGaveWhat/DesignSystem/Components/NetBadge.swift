import SwiftUI

/// Signed balance chip: received tint when ahead, given tint when behind, and a quiet
/// "Even" at zero.
struct NetBadge: View {
    let net: Double
    let currencyCode: String

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
        net.rounded() == 0
            ? Text("Even")
            : Text(verbatim: formattedSignedCurrency(net, code: currencyCode))
    }

    private var foreground: Color {
        net.rounded() == 0 ? Color.textSecondary : appearance.main
    }

    private var tint: Color {
        net.rounded() == 0 ? Color.fillTrack : appearance.tint
    }

    private var appearance: GiftDirectionAppearance {
        (net > 0 ? GiftDirection.received : GiftDirection.given).appearance
    }
}
