import SwiftUI

/// Home before the first gift: a card with the app mark and the only "Add a gift" action,
/// then two tiles on what the app does for you. It follows the data, so the first saved
/// gift replaces it with the timeline.
struct HomeWelcome: View {
    let router: AppRouter
    @Environment(\.compactVerticalSpace) private var isCompact
    private let iconSize: CGFloat = 48

    var body: some View {
        VStack(spacing: WelcomeMetrics.spacing(isCompact: isCompact)) {
            WelcomeCard(
                title: "Add a gift", identifier: "home.welcome.add",
                action: { router.presentNewGift(from: .welcomeCard) }
            ) {
                IconMark(size: isCompact ? 48 : 56)
            }
            WelcomeTiles {
                WelcomeTile(title: "Auto-picked icon") {
                    GiftSquare(emoji: "🎁", tint: Color.receivedTint, size: iconSize, fontSize: 26)
                }
                WelcomeTile(title: "Who gave how much") {
                    InsightsGlyph(size: iconSize)
                }
                .background {
                    BreathingGlow(isActive: router.tab == .home && router.giftSheet == nil)
                }
                // The glow spreads under the neighbouring tile, not over it.
                .zIndex(-1)
            }
            // And under the card above.
            .zIndex(-1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.welcome")
    }
}
