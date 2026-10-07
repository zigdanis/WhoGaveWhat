import SwiftUI

/// Presentation-only row shared by gift lists. Feature code prepares its labels.
struct GiftRow: View {
    let gift: Gift
    let subtitle: String
    let dateLabel: String
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            GiftSquare(emoji: gift.emoji, tint: Color.iconWell)
            VStack(alignment: .leading, spacing: 2) {
                Text(gift.name)
                    .font(Font.app(16, .semibold))
                    .foregroundColor(Color.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Font.app(13, .regular))
                    .foregroundColor(Color.muted3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedCurrency(gift.value, code: currencyCode))
                    .font(Font.app(16, .semibold)).foregroundColor(Color.ink)
                Text(dateLabel)
                    .font(Font.app(12, .regular))
                    .foregroundColor(Color.muted4)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
