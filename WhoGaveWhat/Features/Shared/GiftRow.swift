import SwiftUI

/// Presentation-only row shared by gift lists. Feature code prepares its labels.
/// Names wrap instead of truncating. At accessibility text sizes the value and
/// date move below the names so the name column keeps the full row width.
struct GiftRow: View {
    let gift: Gift
    let subtitle: String
    let dateLabel: String
    let currencyCode: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GiftSquare(emoji: gift.emoji, tint: Color.fillTrack)
            if dynamicTypeSize >= .accessibility1 {
                VStack(alignment: .leading, spacing: 6) {
                    names
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        valueLabel
                        dateText
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                names
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    valueLabel
                    dateText
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(gift.name)
                .font(Font.app(16, .semibold))
                .foregroundColor(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(Font.app(13, .regular))
                .foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var valueLabel: some View {
        Text(formattedCurrency(gift.value, code: currencyCode))
            .font(Font.app(16, .semibold, rounded: true))
            .foregroundColor(Color.textPrimary)
    }

    private var dateText: some View {
        Text(dateLabel)
            .font(Font.app(12, .regular))
            .foregroundColor(Color.textSecondary)
            .lineLimit(1)
    }
}
