import SwiftUI

/// Insights before the first gift: there is nothing to sum up yet, so the card leads to the first gift.
/// The Insights glyph breathes with the glow Home's "Who gave how much" tile promised, and two tiles
/// show the balance chip and comparison bar the sections below will use.
struct InsightsWelcome: View {
    let router: AppRouter
    @Environment(\.compactVerticalSpace) private var isCompact

    var body: some View {
        VStack(spacing: WelcomeMetrics.spacing(isCompact: isCompact)) {
            WelcomeCard(
                title: "Add a gift", identifier: "insights.welcome.add",
                action: { router.presentNewGift(from: .insightsWelcome) }
            ) {
                InsightsGlyph(size: isCompact ? 56 : 72)
            }
            .background {
                BreathingGlow(isActive: router.tab == .insights && router.giftSheet == nil)
            }
            // The glow spreads under the tiles, not over them.
            .zIndex(-1)
            WelcomeTiles {
                WelcomeTile(title: "Balance with each person") {
                    CountBalanceBadge(net: 2)
                        .frame(height: 48)
                }
                WelcomeTile(title: "Compare two people") {
                    PairBar(first: 3, second: 2, firstColor: Color.given, secondColor: Color.received, height: 10)
                        .frame(width: 56, height: 48)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.welcome")
    }
}
