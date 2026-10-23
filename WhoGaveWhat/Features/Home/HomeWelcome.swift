import SwiftUI

/// Home before the first gift: a card with the app mark and the only "Add a gift" action,
/// then two tiles on what the app does for you. It follows the data, so the first saved
/// gift replaces it with the timeline.
struct HomeWelcome: View {
    let router: AppRouter
    @Environment(\.compactVerticalSpace) private var isCompact
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let iconSize: CGFloat = 48

    var body: some View {
        let spacing: CGFloat = isCompact ? 10 : 12
        // Accessibility text sizes need the full width for each label.
        let tiles =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))

        VStack(spacing: spacing) {
            WelcomeCard(router: router, isCompact: isCompact)
            tiles {
                WelcomeTile(title: "Icon picked for you", isCompact: isCompact) {
                    GiftSquare(emoji: "🎁", tint: Color.receivedTint, size: iconSize, fontSize: 26)
                }
                WelcomeTile(title: "Who gave whom how much", isCompact: isCompact) {
                    InsightsGlyph(size: iconSize)
                }
                .background { TileGlow() }
                // The glow spreads under the neighbouring tile, not over it.
                .zIndex(-1)
            }
            // Both tiles take the taller one's height.
            .fixedSize(horizontal: false, vertical: true)
            // And under the card above.
            .zIndex(-1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.welcome")
    }
}

private struct WelcomeCard: View {
    let router: AppRouter
    let isCompact: Bool

    var body: some View {
        Card {
            VStack(spacing: isCompact ? 12 : 16) {
                IconMark(size: isCompact ? 48 : 56)
                    .accessibilityHidden(true)
                Text("Log your first gift")
                    .font(Font.app(20, .bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Button {
                    router.presentNewGift()
                } label: {
                    Label("Add a gift", systemImage: "plus")
                        .font(Font.app(17, .semibold))
                        .foregroundStyle(Color.onFill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isCompact ? 2 : 6)
                }
                // Same cap as the floating button, so the label stays on one line.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Color.brandFill)
                .accessibilityIdentifier("home.welcome.add")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, isCompact ? 18 : 24)
        }
    }
}

/// An informational tile: an icon over a short label, read as one element.
private struct WelcomeTile<Icon: View>: View {
    let title: LocalizedStringKey
    let isCompact: Bool
    @ViewBuilder var icon: Icon

    var body: some View {
        Card {
            VStack(spacing: isCompact ? 8 : 10) {
                icon
                    .accessibilityHidden(true)
                Text(title)
                    .font(Font.app(13, .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Icons line up across tiles even when only one label wraps.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 12)
            .padding(.vertical, isCompact ? 12 : 16)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Insights tab glyph in the brand color.
private struct InsightsGlyph: View {
    let size: CGFloat

    var body: some View {
        Image("Insights")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size * 0.75, height: size * 0.75)
            .foregroundStyle(Color.brand)
            .frame(width: size, height: size)
    }
}

/// A soft brand glow in the tile's shape that breathes slowly. With Reduce Motion it holds still
/// halfway between its quietest and brightest.
private struct TileGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The glow color is brighter against dark backgrounds, so dark mode needs less opacity.
        let opacity: ClosedRange<Double> = colorScheme == .dark ? 0.12...0.55 : 0.15...0.65
        RoundedRectangle(cornerRadius: DesignMetrics.radiusLarge, style: .continuous)
            .fill(Color.brandGlow)
            .phaseAnimator(reduceMotion ? [0.5] : [0.0, 1.0]) { glow, level in
                glow
                    .scaleEffect(1 + 0.03 * level)
                    .opacity(opacity.lowerBound + (opacity.upperBound - opacity.lowerBound) * level)
                    .blur(radius: 8 + 6 * level)
            } animation: { _ in
                .easeInOut(duration: 1.4)
            }
            .accessibilityHidden(true)
    }
}
