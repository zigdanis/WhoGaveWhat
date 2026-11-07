import SwiftUI

/// Signed balance chip: received tint when ahead, given tint when behind, and a quiet
/// "Even" at zero. A balance in several currencies lists each one; when it is ahead in one
/// and behind in another there is no overall direction, so the chip stays neutral.
struct NetBadge: View {
    let net: CurrencyAmounts
    let preferredCurrency: SupportedCurrency

    var body: some View {
        // Several currencies share one line while it fits, as at default text sizes; otherwise,
        // such as at accessibility sizes on a narrow phone, they stack one per line.
        ViewThatFits(in: .horizontal) {
            chip(label, in: Capsule())
            if net.nonZeroCurrencies.count > 1 {
                chip(
                    AmountsText(amounts: net, preferred: preferredCurrency, signed: true, alignment: .trailing),
                    in: RoundedRectangle(cornerRadius: DesignMetrics.radiusSmall, style: .continuous))
            }
        }
        // Sized before its row's label, so it is offered the row's free width rather than a share of it.
        .layoutPriority(1)
    }

    private func chip(_ content: some View, in shape: some Shape) -> some View {
        content
            .font(Font.app(14, .semibold, rounded: true))
            .foregroundColor(foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(shape.fill(tint))
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
