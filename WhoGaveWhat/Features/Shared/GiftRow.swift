import SwiftUI

/// Presentation-only row shared by gift lists. Feature code prepares its labels.
/// Names wrap instead of truncating: the title and "giver → recipient" subtitle
/// may use several lines, and the value/date column keeps its intrinsic width.
struct GiftRow: View {
    let gift: Gift
    let subtitle: String
    let dateLabel: String
    let currencyCode: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GiftSquare(emoji: gift.emoji, tint: Color.fillTrack)
            VStack(alignment: .leading, spacing: 2) {
                Text(gift.name)
                    .font(Font.app(16, .semibold))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(Font.app(13, .regular))
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedCurrency(gift.value, code: currencyCode))
                    .font(Font.app(16, .semibold, rounded: true))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                Text(dateLabel)
                    .font(Font.app(12, .regular))
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
