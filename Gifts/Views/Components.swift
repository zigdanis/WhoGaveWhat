import SwiftUI

/// Circular initials avatar. When selected, draws the white + color double ring
/// (the prototype's `box-shadow: 0 0 0 3px #fff, 0 0 0 5px color`).
struct AvatarView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 44
    var selected: Bool = false

    var body: some View {
        Text(initials)
            .font(KS.font(size * 0.4, .heavy))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .overlay {
                if selected {
                    Circle().stroke(Color.white, lineWidth: 3)
                        .padding(-1.5)
                        .background(Circle().stroke(color, lineWidth: 2).padding(-3.5))
                }
            }
    }
}

/// Rounded tinted square holding a gift emoji.
struct GiftSquare: View {
    let emoji: String
    let tint: Color
    var size: CGFloat = 46
    var corner: CGFloat = 14
    var fontSize: CGFloat = 24

    var body: some View {
        Text(emoji)
            .font(.system(size: fontSize))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(tint))
    }
}

/// Pill chip used for filters, members, celebrations, dates.
struct ChipView: View {
    let label: String
    let selected: Bool
    let accent: Color

    var body: some View {
        Text(label)
            .font(KS.font(14, .heavy))
            .foregroundColor(selected ? .white : Color(hex: 0x7A7066))
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(selected ? accent : KS.card)
            )
            .overlay(
                Capsule().stroke(selected ? accent : KS.border, lineWidth: 1.5)
            )
            .fixedSize()
    }
}

/// Thin progress bar with min 4% width.
struct BarView: View {
    let pct: Double      // 0...100
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(color)
                .frame(width: max(geo.size.width * CGFloat(max(pct, 4) / 100), height))
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Capsule().fill(KS.track))
    }
}

/// Uppercase muted section header.
struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(KS.font(12.5, .heavy))
            .tracking(0.7)
            .foregroundColor(KS.muted4)
            .padding(.horizontal, 4)
    }
}

/// White rounded card container.
struct Card<Content: View>: View {
    var corner: CGFloat = 22
    var strongShadow: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(KS.card))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .ksCardShadow(strong: strongShadow)
    }
}

/// A single gift row (used in Home timeline and Person detail).
struct GiftRow: View {
    @EnvironmentObject var store: AppStore
    let gift: Gift

    var body: some View {
        let fm = store.flowMeta(gift.flow)
        HStack(spacing: 13) {
            GiftSquare(emoji: gift.emoji, tint: fm.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(gift.name)
                    .font(KS.font(16, .heavy))
                    .foregroundColor(KS.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(fm.arrow)
                        .font(KS.font(14, .black))
                        .foregroundColor(fm.main)
                    Text(store.giftSubtitle(gift))
                        .font(KS.font(13, .bold))
                        .foregroundColor(KS.muted3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(rub(gift.value)).font(KS.font(15, .black)).foregroundColor(KS.ink)
                Text(store.giftMeta(gift))
                    .font(KS.font(12, .bold))
                    .foregroundColor(KS.muted4)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }
}

/// Thin hairline divider between rows in a card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(KS.hairline).frame(height: 1)
    }
}
