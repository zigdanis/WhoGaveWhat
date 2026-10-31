import SwiftUI
import UIKit

/// How wide the window is and what kind of device holds it. Read once at the root, so sheets see the
/// window's size class rather than their own: an iPad form sheet can report compact width.
struct AdaptiveLayout: Equatable {
    var isRegularWidth = false
    var isPad = false

    /// Regular-width windows — iPad and iPhone Duo's inner display — present the gift and person pickers as
    /// popovers next to the row that opened them and keep Save in the sheet header, above the keyboard.
    var usesFormSheets: Bool { isRegularWidth }

    /// Only an iPad window of regular width moves the add actions to the top toolbar. iPhone Duo's inner
    /// display is held in the hands, so its floating button stays at the bottom, within thumb reach.
    var placesAddActionInToolbar: Bool { isPad && isRegularWidth }
}

extension EnvironmentValues {
    @Entry var adaptiveLayout = AdaptiveLayout()
}

extension View {
    /// Publishes `adaptiveLayout` from this root view's size class to everything below it, including sheets.
    func measuresAdaptiveLayout() -> some View {
        modifier(AdaptiveLayoutReader())
    }

    /// A tab's root title. Regular-width windows draw it as a `ScreenHeading` inside the content column,
    /// because the bar's large title stays pinned to the window edge while the content is centered.
    func tabRootTitle(_ title: LocalizedStringKey) -> some View {
        modifier(TabRootTitle(title: title))
    }
}

private struct AdaptiveLayoutReader: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.environment(
            \.adaptiveLayout,
            AdaptiveLayout(
                isRegularWidth: horizontalSizeClass == .regular,
                isPad: UIDevice.current.userInterfaceIdiom == .pad))
    }
}

private struct TabRootTitle: ViewModifier {
    let title: LocalizedStringKey
    @Environment(\.adaptiveLayout) private var layout

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            // The title still names the window, the back button's menu and VoiceOver's screen change. A large
            // title ignores `toolbar(removing:)`, so the bar switches to inline first.
            .navigationBarTitleDisplayMode(layout.isRegularWidth ? .inline : .automatic)
            .toolbar(removing: layout.isRegularWidth ? .title : nil)
    }
}

/// The large tab title drawn inside the content column, aligned with the cards' leading edge. Shown only
/// in regular-width windows, where `tabRootTitle` removes the bar's own title.
struct ScreenHeading: View {
    let title: LocalizedStringKey
    /// Applied only while the heading shows, so compact windows get no extra gap.
    var bottomSpacing: CGFloat = 4
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        if layout.isRegularWidth {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, bottomSpacing)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// `ScreenHeading` as the first section of an inset-grouped `List`, flush with the cards below it.
struct ScreenHeadingSection: View {
    let title: LocalizedStringKey
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        if layout.isRegularWidth {
            Section {
                ScreenHeading(title: title)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }
}

/// The add action of a tab, in the top toolbar of a regular-width iPad window.
struct ToolbarAddButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Not a `Label`: toolbars draw labels icon-only, and the title is what makes the action findable.
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text(title)
            }
            .font(Font.app(16, .semibold))
            .foregroundStyle(Color.onFill)
            .padding(.horizontal, 6)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .buttonStyle(.glassProminent)
        .tint(Color.brandFill)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel(Text(title))
    }
}

/// Size of a picker shown as a popover in a regular-width window.
enum PickerPopover {
    static let width: CGFloat = 360
    private static let header: CGFloat = 56
    private static let padding: CGFloat = 32
    private static let row: CGFloat = 57
    private static let addField: CGFloat = 76
    private static let maxHeight: CGFloat = 540

    /// Fits a header, an optional add field and `rows` person-sized rows; longer lists scroll.
    static func listHeight(rows: Int, addField hasAddField: Bool = false) -> CGFloat {
        min(maxHeight, header + padding + (hasAddField ? addField : 0) + CGFloat(rows) * row)
    }
}
