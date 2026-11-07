import SwiftUI

/// Signed balance chip: received tint when ahead, given tint when behind, and a quiet
/// "Even" at zero. A balance in several currencies lists each one; when it is ahead in one
/// and behind in another there is no overall direction, so the chip stays neutral.
struct NetBadge: View {
    let net: CurrencyAmounts
    let preferredCurrency: SupportedCurrency

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
        net.isEven
            ? Text("Even")
            : Text(verbatim: formattedSignedAmounts(net, preferred: preferredCurrency))
    }

    private var foreground: Color {
        switch net.sign {
        case .even: Color.textSecondary
        case .mixed: Color.textPrimary
        case .positive: GiftDirection.received.appearance.main
        case .negative: GiftDirection.given.appearance.main
        }
    }

    private var tint: Color {
        switch net.sign {
        case .even, .mixed: Color.fillTrack
        case .positive: GiftDirection.received.appearance.tint
        case .negative: GiftDirection.given.appearance.tint
        }
    }
}
