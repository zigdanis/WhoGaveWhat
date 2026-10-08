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
            .layoutPriority(1)
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
    @State private var leadingActionWidth: CGFloat = 0
    @State private var trailingActionWidth: CGFloat = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontallyCenteredHeader
            horizontallyGroupedActionsHeader
            verticallyStackedHeader
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: IntrinsicModalHeaderHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    private var horizontallyCenteredHeader: some View {
        HStack(spacing: 8) {
            leadingActionColumn
            titleLabel
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity)
            trailingActionColumn
        }
        .frame(minHeight: 56)
    }

    private var horizontallyGroupedActionsHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                leadingAction
                Spacer(minLength: 0)
                trailingAction
            }
            titleLabel
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 56)
    }

    private var verticallyStackedHeader: some View {
        VStack(spacing: 6) {
            leadingAction
            trailingAction
            titleLabel
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 56)
    }

    private var actionColumnWidth: CGFloat {
        max(leadingActionWidth, trailingActionWidth)
    }

    @ViewBuilder
    private var leadingActionColumn: some View {
        if leadingActionTitle != nil, onLeadingAction != nil {
            leadingAction.frame(width: actionColumnWidth, alignment: .leading)
        } else {
            Color.clear
                .frame(width: actionColumnWidth, height: 1)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var trailingActionColumn: some View {
        if trailingActionTitle != nil, onTrailingAction != nil {
            trailingAction.frame(width: actionColumnWidth, alignment: .trailing)
        } else {
            Color.clear
                .frame(width: actionColumnWidth, height: 1)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var leadingAction: some View {
        if let leadingActionTitle, let onLeadingAction {
            headerAction(
                title: leadingActionTitle,
                action: onLeadingAction,
                accessibilityIdentifier: leadingActionAccessibilityIdentifier
            )
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                guard abs(width - leadingActionWidth) > 0.5 else { return }
                leadingActionWidth = width
            }
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if let trailingActionTitle, let onTrailingAction {
            headerAction(
                title: trailingActionTitle,
                action: onTrailingAction,
                accessibilityIdentifier: trailingActionAccessibilityIdentifier
            )
            .disabled(!trailingActionIsEnabled)
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                guard abs(width - trailingActionWidth) > 0.5 else { return }
                trailingActionWidth = width
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
