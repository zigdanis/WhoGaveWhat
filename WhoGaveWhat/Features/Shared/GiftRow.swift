import SwiftUI

/// Presentation-only row shared by gift lists. Feature code prepares its labels.
struct GiftRow: View {
    let gift: Gift
    let subtitle: String
    let dateLabel: String

    var body: some View {
        HStack(spacing: 12) {
            GiftSquare(emoji: gift.emoji, tint: KS.iconWell)
            VStack(alignment: .leading, spacing: 2) {
                Text(gift.name)
                    .font(KS.font(16, .semibold))
                    .foregroundColor(KS.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(KS.font(13, .regular))
                    .foregroundColor(KS.muted3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(rub(gift.value)).font(KS.font(16, .semibold)).foregroundColor(KS.ink)
                Text(dateLabel)
                    .font(KS.font(12, .regular))
                    .foregroundColor(KS.muted4)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
