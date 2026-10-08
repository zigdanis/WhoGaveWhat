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
    let leadingActionAccessibilityIdentifier: String?
    let trailingActionTitle: LocalizedStringResource?
    let onTrailingAction: (() -> Void)?
    let trailingActionIsEnabled: Bool
    let trailingActionAccessibilityIdentifier: String?
    let titleAccessibilityIdentifier: String?
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringResource,
        leadingActionTitle: LocalizedStringResource? = nil,
        onLeadingAction: (() -> Void)? = nil,
        leadingActionAccessibilityIdentifier: String? = nil,
        trailingActionTitle: LocalizedStringResource? = nil,
        onTrailingAction: (() -> Void)? = nil,
        trailingActionIsEnabled: Bool = true,
        trailingActionAccessibilityIdentifier: String? = nil,
        titleAccessibilityIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.leadingActionTitle = leadingActionTitle
        self.onLeadingAction = onLeadingAction
        self.leadingActionAccessibilityIdentifier = leadingActionAccessibilityIdentifier
        self.trailingActionTitle = trailingActionTitle
        self.onTrailingAction = onTrailingAction
        self.trailingActionIsEnabled = trailingActionIsEnabled
        self.trailingActionAccessibilityIdentifier = trailingActionAccessibilityIdentifier
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            IntrinsicModalHeader(
                title: title,
                leadingActionTitle: leadingActionTitle,
                onLeadingAction: onLeadingAction,
                leadingActionAccessibilityIdentifier: leadingActionAccessibilityIdentifier,
                trailingActionTitle: trailingActionTitle,
                onTrailingAction: onTrailingAction,
                trailingActionIsEnabled: trailingActionIsEnabled,
                trailingActionAccessibilityIdentifier: trailingActionAccessibilityIdentifier,
                titleAccessibilityIdentifier: titleAccessibilityIdentifier
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
    let leadingActionAccessibilityIdentifier: String?
    let trailingActionTitle: LocalizedStringResource?
    let onTrailingAction: (() -> Void)?
    let trailingActionIsEnabled: Bool
    let trailingActionAccessibilityIdentifier: String?
    let titleAccessibilityIdentifier: String?

    var body: some View {
        ZStack {
            HStack {
                if let leadingActionTitle, let onLeadingAction {
                    headerAction(
                        title: leadingActionTitle,
                        action: onLeadingAction,
                        accessibilityIdentifier: leadingActionAccessibilityIdentifier
                    )
                    Spacer(minLength: 0)
                    if let trailingActionTitle, let onTrailingAction {
                        headerAction(
                            title: trailingActionTitle,
                            action: onTrailingAction,
                            accessibilityIdentifier: trailingActionAccessibilityIdentifier
                        )
                        .disabled(!trailingActionIsEnabled)
                    } else {
                        headerAction(
                            title: leadingActionTitle,
                            action: onLeadingAction,
                            accessibilityIdentifier: nil
                        )
                        .hidden()
                        .accessibilityHidden(true)
                    }
                }
            }
            titleLabel
                .padding(.horizontal, 96)
                .allowsHitTesting(false)
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
            .accessibilityIdentifier(titleAccessibilityIdentifier ?? "")
    }

    private func headerAction(
        title: LocalizedStringResource,
        action: @escaping () -> Void,
        accessibilityIdentifier: String?
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
        }
        .buttonStyle(.bordered)
        .tint(Color.muted2)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}
