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
                    .navigationTitle("Who gave what")
            }
            stack(.people, "People", image: "People") {
                // People is its own native List (swipe-to-delete a person), so it
                // carries its own background + floating button like Home.
                PeopleView(composition: composition)
                    .navigationTitle("People")
            }
            stack(.insights, "Insights", image: "Insights") {
                // Insights is a read-only summary, so it has no floating "Add a gift" button.
                ScreenScroll { InsightsView(composition: composition) }
                    .navigationTitle("Insights")
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
            set: { composition.router.giftSheet = $0 })
    }
}

/// Shared scroll container for a tab's root screen — content scrolls under the
/// floating glass tab bar.
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .readableColumn()
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(Color.appBackground)
    }
}

/// The floating "Add a gift" button, pinned just above the tab bar on Home.
struct AddGiftFAB: View {
    let router: AppRouter

    var body: some View {
        FloatingActionButton(title: "Add a gift", systemImage: "plus") {
            router.presentNewGift()
        }
        .accessibilityLabel("Add a gift")
    }
}

extension View {
    /// Pin the floating "Add a gift" button above the tab bar while `isVisible`.
    func floatingAddButton(composition: AppComposition, isVisible: Bool = true) -> some View {
        safeAreaInset(edge: .bottom) {
            if isVisible { AddGiftFAB(router: composition.router) }
        }
    }
}
