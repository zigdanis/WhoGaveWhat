import SwiftUI

/// Shown on Home, People and Insights when the gifts and people could not be loaded: in place of the
/// first-run welcome before any load succeeded, or above the last loaded records after a later load
/// failed. It never presents the journal as empty.
struct LoadFailedCard: View {
    let retry: () -> Void
    @Environment(\.compactVerticalSpace) private var isCompact

    var body: some View {
        Card {
            VStack(spacing: isCompact ? 10 : 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.even)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Couldn't load your gifts")
                        .font(Font.app(17, .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("They are still saved on this device. Try again in a moment.")
                        .font(Font.app(14, .regular))
                        .foregroundStyle(Color.textSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                RetryButton(identifier: "data.retry", action: retry)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, isCompact ? 16 : 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("data.load-failed")
    }
}

/// `LoadFailedCard` as a full-width row at the top of a tab's `List`, spaced like the welcomes.
struct LoadFailedListSection: View {
    let retry: () -> Void

    var body: some View {
        Section {
            LoadFailedCard(retry: retry)
                .padding(.horizontal, WelcomeMetrics.horizontalInset)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .zeroHorizontalListSectionMargins()
    }
}

/// The prominent "Try again" action of the load and store failures.
struct RetryButton: View {
    let identifier: String
    let action: () -> Void
    @Environment(\.haptics) private var haptics

    var body: some View {
        Button {
            haptics.play(.softImpact)
            action()
        } label: {
            Label("Try again", systemImage: "arrow.clockwise")
                .font(Font.app(17, .semibold))
                .foregroundStyle(Color.onFill)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        // Same cap as the welcome card's action, so the label stays on one line.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .prominentGlassButtonStyle()
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.brandFill)
        .accessibilityIdentifier(identifier)
    }
}
