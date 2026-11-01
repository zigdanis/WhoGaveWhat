import SwiftUI

/// Building blocks of the first-run welcomes on Home, People and Insights: a card with a hero and one
/// prominent action, then small informational tiles.
enum WelcomeMetrics {
    /// Space between the card and the tiles, and between the tiles.
    static func spacing(isCompact: Bool) -> CGFloat { isCompact ? 10 : 12 }
    /// Each welcome sits this far from the screen edges, so a tile's glow has room inside its row.
    static let horizontalInset: CGFloat = 24
}

/// A quiet text action under the card's main button.
struct WelcomeSecondaryAction {
    let title: LocalizedStringKey
    let identifier: String
    let action: () -> Void
}

/// The welcome card: a decorative hero over the screen's one prominent action.
struct WelcomeCard<Hero: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    var secondary: WelcomeSecondaryAction?
    let action: () -> Void
    @ViewBuilder var hero: Hero
    @Environment(\.compactVerticalSpace) private var isCompact
    @Environment(\.haptics) private var haptics

    var body: some View {
        Card {
            VStack(spacing: isCompact ? 16 : 20) {
                // Decorative: the buttons are the card's only elements for VoiceOver.
                hero
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Button {
                        haptics.play(.softImpact)
                        action()
                    } label: {
                        Label(title, systemImage: "plus")
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
                    .accessibilityIdentifier(identifier)
                    if let secondary {
                        Button {
                            haptics.play(.softImpact)
                            secondary.action()
                        } label: {
                            Text(secondary.title)
                                .font(Font.app(14, .regular))
                                .foregroundStyle(Color.brand)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(secondary.identifier)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, isCompact ? 18 : 24)
            // The text action carries its own 44 pt target, which already leaves room below.
            .padding(.bottom, secondary == nil ? (isCompact ? 16 : 20) : (isCompact ? 6 : 10))
        }
    }
}

/// Tiles side by side, stacked at accessibility text sizes, all as tall as the tallest.
struct WelcomeTiles<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.compactVerticalSpace) private var isCompact
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let spacing = WelcomeMetrics.spacing(isCompact: isCompact)
        // Accessibility text sizes need the full width for each label.
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
            // Both tiles take the taller one's height.
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An informational tile: an icon over a short label, read as one element.
struct WelcomeTile<Icon: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var icon: Icon
    @Environment(\.compactVerticalSpace) private var isCompact

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
struct InsightsGlyph: View {
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

/// A soft brand glow in a card's shape that breathes slowly while `isActive`, which callers set while
/// their screen is in front. In the background, with Reduce Motion or while inactive it holds still
/// halfway between its quietest and brightest.
struct BreathingGlow: View {
    let isActive: Bool
    var cornerRadius: CGFloat = DesignMetrics.radiusLarge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    /// When the current pulse began; `distantFuture` while it is off, so a resuming frame rests at 0.5.
    @State private var pulseStart = Date.distantFuture

    var body: some View {
        // The glow color is brighter against dark backgrounds, so dark mode needs less opacity.
        let opacity: ClosedRange<Double> = colorScheme == .dark ? 0.12...0.55 : 0.15...0.65
        let isPulsing = !reduceMotion && scenePhase == .active && isActive
        // A paused timeline asks for no frames, so nothing animates while the pulse is off.
        TimelineView(.animation(paused: !isPulsing)) { context in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.brandGlow)
                .glowLevel(isPulsing ? Self.level(at: context.date, since: pulseStart) : 0.5, opacity: opacity)
        }
        // Eases into the resting glow instead of snapping when a sheet slides up; Reduce Motion stays instant.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isPulsing)
        .onChange(of: isPulsing, initial: true) { _, pulsing in
            pulseStart = pulsing ? .now : .distantFuture
        }
        .accessibilityHidden(true)
    }

    /// Breathes on a 2.8-second cycle, rising from the resting level so a resumed pulse never jumps.
    /// The first frame after resuming renders before `onChange` stamps the new start; the stale
    /// `distantFuture` start clamps to zero elapsed time, which is the resting level.
    private static func level(at date: Date, since start: Date) -> Double {
        0.5 + 0.5 * sin(2 * .pi * max(0, date.timeIntervalSince(start)) / 2.8)
    }
}

extension View {
    /// The glow at `level`, from 0 (quietest) to 1 (brightest).
    fileprivate func glowLevel(_ level: Double, opacity: ClosedRange<Double>) -> some View {
        scaleEffect(1 + 0.03 * level)
            .opacity(opacity.lowerBound + (opacity.upperBound - opacity.lowerBound) * level)
            .blur(radius: 8 + 6 * level)
    }
}
