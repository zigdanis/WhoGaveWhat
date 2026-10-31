import SwiftUI

/// Native iOS 26 shell: a Liquid Glass tab bar floating over four navigation
/// stacks (Home, People, Insights, Settings), with a floating "Add a gift" glass button
/// pinned just above it on Home. Person detail is a native push; "Add a gift"
/// is a native sheet.
struct RootAppView: View {
    let composition: AppComposition

    var body: some View {
        TabView(selection: tabSelection) {
            stack(.home, "Home", image: "Home") {
                // Home is its own native List (smooth swipe-to-delete), so it
                // carries its own background and the floating "Add a gift" button.
                HomeView(composition: composition)
                    .tabRootTitle("Who gave what")
            }
            stack(.people, "People", image: "People") {
                // People is its own native List (swipe-to-delete a person), so it
                // carries its own background + floating button like Home.
                PeopleView(composition: composition)
                    .tabRootTitle("People")
            }
            stack(.insights, "Insights", image: "Insights") {
                // Insights is a read-only summary, so it has no floating "Add a gift" button.
                ScreenScroll(maxWidth: InsightsLayout.twoColumnMaxWidth) {
                    InsightsView(composition: composition)
                }
                .tabRootTitle("Insights")
            }
            // Settings is a preferences screen, so it has no floating "Add a gift" button.
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView(composition: composition)
                }
            }
        }
        .tint(Color.brand)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: giftSheetBinding) { route in
            AddGiftSheet(route: route, composition: composition)
        }
    }

    /// One tab: a navigation stack that pushes `PersonDetailView` for any entity id.
    /// `image` is a custom (template-rendered) asset name from `Assets.xcassets`.
    private func stack<Content: View>(
        _ value: AppTab, _ title: LocalizedStringKey, image: String,
        @ViewBuilder _ content: () -> Content
    ) -> some TabContent<AppTab> {
        Tab(title, image: image, value: value) {
            NavigationStack {
                content()
                    .navigationDestination(for: String.self) { id in
                        PersonDetailView(entityId: id, composition: composition)
                    }
                    .navigationDestination(for: Gift.self) { gift in
                        GiftDetailView(giftId: gift.id, composition: composition)
                    }
            }
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(get: { composition.router.tab }, set: { composition.router.selectTab($0) })
    }

    private var giftSheetBinding: Binding<GiftSheetRoute?> {
        Binding(
            get: { composition.router.giftSheet },
            // Only a dismissal arrives here; presenting goes through the router's tracked methods.
            set: { if $0 == nil { composition.router.dismissGiftSheet() } })
    }
}

/// Shared scroll container for a tab's root screen — content scrolls under the
/// floating glass tab bar.
struct ScreenScroll<Content: View>: View {
    var maxWidth: CGFloat = ReadableWidth.content
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .readableColumn(maxWidth: maxWidth)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(Color.appBackground)
    }
}

/// The floating "Add a gift" button, pinned just above the tab bar on Home.
/// A regular-width iPad window shows `ToolbarAddButton` in the top toolbar instead.
struct AddGiftFAB: View {
    let router: AppRouter

    var body: some View {
        FloatingActionButton(title: "Add a gift", systemImage: "plus") {
            router.presentNewGift(from: .floatingButton)
        }
        .accessibilityLabel("Add a gift")
    }
}

extension View {
    /// The "Add a gift" action while `isVisible`: pinned above the bottom tab bar, or in the top toolbar of a
    /// regular-width iPad window, where the tab bar sits at the top and the bottom center is out of reach.
    func addGiftAction(composition: AppComposition, isVisible: Bool = true) -> some View {
        modifier(AddGiftAction(router: composition.router, isVisible: isVisible))
    }
}

private struct AddGiftAction: ViewModifier {
    let router: AppRouter
    let isVisible: Bool
    @Environment(\.adaptiveLayout) private var layout

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if isVisible && !layout.placesAddActionInToolbar { AddGiftFAB(router: router) }
            }
            .toolbar {
                if isVisible && layout.placesAddActionInToolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ToolbarAddButton(title: "Add a gift") {
                            router.presentNewGift(from: .toolbarButton)
                        }
                    }
                }
            }
    }
}
