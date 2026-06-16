import SwiftUI

/// Rounded-square initials avatar (8px corners) — avatars are rounded squares,
/// never circles. When selected, draws the white + colour double ring.
struct AvatarView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 44
    var selected: Bool = false

    var body: some View {
        Text(initials)
            .font(KS.font(size * 0.4, .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(color))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                        .stroke(Color.white, lineWidth: 3)
                        .padding(-1.5)
                        .background(
                            RoundedRectangle(cornerRadius: KS.radius + 2, style: .continuous)
                                .stroke(color, lineWidth: 2).padding(-3.5)
                        )
                }
            }
    }
}

/// Rounded tinted square holding a gift emoji.
struct GiftSquare: View {
    let emoji: String
    let tint: Color
    var size: CGFloat = 44
    var corner: CGFloat = KS.radius
    var fontSize: CGFloat = 23

    var body: some View {
        Text(emoji)
            .font(.system(size: fontSize))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(tint))
    }
}

/// Native-feeling segmented control: a #EFEFF1 track with a white selected pill.
struct Segmented: View {
    struct Option { let key: String; let label: String; let accent: Color }
    let options: [Option]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.key) { o in
                let sel = o.key == selected
                Button { onSelect(o.key) } label: {
                    Text(LocalizedStringKey(o.label))
                        .font(KS.font(14, .semibold))
                        // Selected segment fills with the app's bright green so the
                        // active state reads at a glance; others stay quiet grey.
                        .foregroundColor(sel ? .white : KS.chipText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(sel ? KS.emerald : Color.clear)
                                .shadow(color: sel ? KS.emerald.opacity(0.35) : .clear, radius: 2, x: 0, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KS.track))
    }
}

/// Thin progress bar with a min visible width, sitting on a track.
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

/// Quiet, lowercase grouped-list section label (13px regular, secondary grey).
struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(KS.font(13, .regular))
            .foregroundColor(KS.muted)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// White grouped card (8px corners). Flat on the field by default; `strongShadow`
/// lifts onboarding tiles.
struct Card<Content: View>: View {
    var corner: CGFloat = KS.radius
    var strongShadow: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(KS.card))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .modifier(OptionalLift(on: strongShadow))
    }
}

private struct OptionalLift: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.ksCardShadow(strong: true) } else { content }
    }
}

/// A single gift row (used in Home timeline and Person detail).
struct GiftRow: View {
    @EnvironmentObject var store: AppStore
    let gift: Gift

    var body: some View {
        let fm = store.flowMeta(gift.flow)
        HStack(spacing: 12) {
            GiftSquare(emoji: gift.emoji, tint: fm.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(gift.name)
                    .font(KS.font(16, .semibold))
                    .foregroundColor(KS.ink)
                    .lineLimit(1)
                Text(store.giftSubtitle(gift))
                    .font(KS.font(13, .regular))
                    .foregroundColor(KS.muted3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(rub(gift.value)).font(KS.font(16, .semibold)).foregroundColor(KS.ink)
                Text(store.giftMeta(gift))
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

/// Swipe-left to reveal a destructive Delete action, for rows in a custom card
/// stack. iOS 26 has no `swipeActionsContainer` (that's iOS 27+), so this is a
/// manual drag-driven reveal. A plain tap still passes through to the row (the
/// drag needs real horizontal travel), and Delete asks for confirmation first.
struct SwipeToDelete<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var committed: CGFloat = 0
    @State private var confirm = false
    private let actionWidth: CGFloat = 84

    var body: some View {
        ZStack(alignment: .trailing) {
            Button { confirm = true } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(hex: 0xE5484D))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(offset < 0 ? 1 : 0)

            content
                .background(KS.card)
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { v in
                            // Only react to a clearly-horizontal drag, so vertical
                            // scrolling is never hijacked.
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            offset = min(0, max(-actionWidth, committed + v.translation.width))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                offset = offset < -actionWidth / 2 ? -actionWidth : 0
                                committed = offset
                            }
                        }
                )
        }
        .clipShape(Rectangle())
        .confirmationDialog("Delete this gift?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { offset = 0; committed = 0 }
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}

/// Thin hairline divider between rows in a card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(KS.sep).frame(height: 1)
    }
}

/// Trailing disclosure chevron used on tappable rows.
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(KS.chevron)
    }
}

/// Telegram-style spoiler cover: a frosted tile speckled with softly twinkling
/// particles. Driven by `TimelineView(.animation)` so it animates continuously
/// with no restart — the old repeating linear shimmer snapped at every loop,
/// which read as a jitter. Compact by default (a small eye-off glyph); pass a
/// `label` for a wider "Tap to reveal"-style cover.
struct SpoilerCover: View {
    var label: String? = nil

    /// Fixed pseudo-random particle field (normalized position, twinkle phase,
    /// size). Stable frame-to-frame, so only the twinkle animates — never the
    /// layout. Seeded by index via a hash-style sine so it needs no RNG.
    private static let particles: [(x: CGFloat, y: CGFloat, phase: Double, scale: CGFloat)] =
        (0..<90).map { i in
            let fx = sin(Double(i) * 12.9898) * 43758.5453
            let fy = sin(Double(i) * 78.2330) * 12543.1234
            let fp = sin(Double(i) * 3.14159) * 9999.0
            return (x: CGFloat(fx - fx.rounded(.down)),
                    y: CGFloat(fy - fy.rounded(.down)),
                    phase: (fp - fp.rounded(.down)) * 2 * .pi,
                    scale: 0.7 + CGFloat(i % 3) * 0.35)
        }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(Color(hex: 0xE4E7EC))
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    for p in Self.particles {
                        let tw = (sin(t * 2.4 + p.phase) + 1) / 2          // 0…1 twinkle
                        let r = p.scale * (0.55 + 0.65 * tw)
                        let pt = CGPoint(x: p.x * size.width, y: p.y * size.height)
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                                 with: .color(KS.muted2.opacity(0.22 + 0.45 * tw)))
                    }
                }
            }
            if let label {
                Text(LocalizedStringKey(label))
                    .font(KS.font(12.5, .semibold)).foregroundColor(KS.muted2)
            } else {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(KS.muted2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: KS.radius, style: .continuous))
    }
}

/// A money amount hidden behind a tap-to-reveal shimmer. Each instance keeps its
/// own reveal state, so every row reveals independently. A high-priority tap wins
/// over an enclosing NavigationLink/row button; once revealed it stops
/// intercepting, so taps then fall through to the row (e.g. to push detail).
struct AmountSpoiler: View {
    let amount: Double
    var font: Font = KS.font(16, .semibold)
    var color: Color = KS.ink
    @State private var revealed = false

    var body: some View {
        Text(rub(amount))
            .font(font).foregroundColor(color)
            .blur(radius: revealed ? 0 : 7)
            .overlay {
                if !revealed {
                    SpoilerCover().padding(.horizontal, -8).padding(.vertical, -3)
                }
            }
            .contentShape(Rectangle())
            .modifier(RevealOnTap(revealed: $revealed))
            .accessibilityLabel(revealed ? rub(amount) : String(localized: "Hidden amount, tap to reveal"))
    }
}

private struct RevealOnTap: ViewModifier {
    @Binding var revealed: Bool
    func body(content: Content) -> some View {
        if revealed {
            content
        } else {
            content.highPriorityGesture(
                TapGesture().onEnded {
                    withAnimation(.easeInOut(duration: 0.35)) { revealed = true }
                }
            )
        }
    }
}

/// Triangle from three normalized (0…1) points within the frame.
private struct TriangleShape: Shape {
    let pts: [CGPoint]
    func path(in r: CGRect) -> Path {
        var p = Path()
        let m = pts.map { CGPoint(x: r.minX + $0.x * r.width, y: r.minY + $0.y * r.height) }
        p.move(to: m[0]); p.addLine(to: m[1]); p.addLine(to: m[2]); p.closeSubpath()
        return p
    }
}

/// The app's logo mark: ink tile with a white "give" triangle (↑) over an
/// emerald "take" triangle (↓). Geometry matches `Gift Icon.dc.html`.
struct IconMark: View {
    var size: CGFloat
    var corner: CGFloat { size * 0.15 }

    private let give: [CGPoint] = [CGPoint(x: 0.45275, y: 0.238),
                                   CGPoint(x: 0.6715, y: 0.531),
                                   CGPoint(x: 0.234, y: 0.531)]
    private let take: [CGPoint] = [CGPoint(x: 0.328, y: 0.57),
                                   CGPoint(x: 0.7655, y: 0.57),
                                   CGPoint(x: 0.54675, y: 0.863)]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(KS.ink)
            TriangleShape(pts: give).fill(Color.white)
            TriangleShape(pts: take).fill(KS.emerald)
        }
        .frame(width: size, height: size)
    }
}
