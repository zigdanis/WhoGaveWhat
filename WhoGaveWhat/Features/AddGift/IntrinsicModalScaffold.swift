import SwiftUI

struct IntrinsicModalHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 56

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A sheet root whose vertical ideal size comes only from its header and content.
/// Unlike a navigation container, it does not claim the presenter's full height.
struct IntrinsicModalScaffold<Content: View>: View {
    let title: LocalizedStringResource
    let leadingActionTitle: LocalizedStringResource?
    let onLeadingAction: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringResource,
        leadingActionTitle: LocalizedStringResource? = nil,
        onLeadingAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.leadingActionTitle = leadingActionTitle
        self.onLeadingAction = onLeadingAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            IntrinsicModalHeader(
                title: title,
                leadingActionTitle: leadingActionTitle,
                onLeadingAction: onLeadingAction
            )
            content
        }
        .background(Color.bg)
    }
}

private struct IntrinsicModalHeader: View {
    let title: LocalizedStringResource
    let leadingActionTitle: LocalizedStringResource?
    let onLeadingAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let leadingActionTitle, let onLeadingAction {
                headerAction(title: leadingActionTitle, action: onLeadingAction)
                Spacer(minLength: 0)
                titleLabel
                Spacer(minLength: 0)
                headerAction(title: leadingActionTitle, action: onLeadingAction)
                    .hidden()
                    .accessibilityHidden(true)
            } else {
                titleLabel
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: IntrinsicModalHeaderHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func headerAction(
        title: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
        }
        .buttonStyle(.bordered)
        .tint(Color.muted2)
    }
}
