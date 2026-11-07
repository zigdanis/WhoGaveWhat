import SwiftUI

/// The root while the store could not be opened. The records stay where they are; Retry opens the
/// store again, and nothing is deleted or reset on the way.
struct StoreUnavailableView: View {
    let retry: () -> Void
    @Environment(\.compactVerticalSpace) private var isCompact

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                message
                    // Centered in the window, scrolling only when large text needs more room.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.appBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("store.unavailable")
    }

    private var message: some View {
        VStack(spacing: isCompact ? 16 : 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: isCompact ? 36 : 48, weight: .semibold))
                .foregroundStyle(Color.even)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Can't open your gifts")
                    .font(Font.app(24, .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Your gifts and people are still saved on this device, and nothing was deleted. Try again in a moment. If this keeps happening, restart the device."
                )
                .font(Font.app(16, .regular))
                .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            RetryButton(identifier: "store.retry", action: retry)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: ReadableWidth.content)
    }
}

/// The root during a Retry: the store is opening again.
struct StoreOpeningView: View {
    var body: some View {
        ProgressView {
            Text("Opening your gifts…")
                .font(Font.app(15, .regular))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .accessibilityIdentifier("store.opening")
    }
}
