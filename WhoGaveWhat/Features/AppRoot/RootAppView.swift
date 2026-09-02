import SwiftUI

/// Native iOS 26 shell: a Liquid Glass tab bar floating over three navigation
/// stacks, with a floating "Add a gift" pill pinned just above it. Person detail
/// is a native push; "Add a gift" and Settings are native sheets.
struct RootAppView: View {
    let composition: AppComposition

    var body: some View {
        TabView(selection: tabSelection) {
            stack(.home, "Home", "Home") {
                // Home is its own native List (smooth swipe-to-delete), so it
                // carries its own background + floating button rather than the
                // shared ScreenScroll wrapper.
                HomeView(composition: composition)
            }
            stack(.people, "People", "People") {
                // People is its own native List (swipe-to-delete a person), so it
                // carries its own background + floating button like Home.
                PeopleView(composition: composition)
                    .navigationTitle("People")
            }
            stack(.insights, "Insights", "Insights") {
                ScreenScroll(composition: composition) { InsightsView(composition: composition) }
                    .navigationTitle("Insights")
            }
        }
        .tint(Color.recv)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(item: giftSheetBinding) { route in
            AddGiftSheet(route: route, composition: composition)
        }
        .sheet(isPresented: settingsBinding) { SettingsView(composition: composition) }
    }

    /// One tab: a navigation stack that pushes `PersonDetailView` for any entity id.
    /// `icon` is a custom (template-rendered) asset name from `Assets.xcassets`.
    @ViewBuilder
    private func stack<Content: View>(_ value: AppTab, _ title: String, _ icon: String,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: String.self) { id in
                    PersonDetailView(entityId: id, composition: composition)
                }
                .navigationDestination(for: Gift.self) { gift in
                    GiftDetailView(giftId: gift.id, composition: composition)
                }
        }
        .tabItem { Label(LocalizedStringKey(title), image: icon) }
        .tag(value)
    }

    private var tabSelection: Binding<AppTab> {
        Binding(get: { composition.router.tab }, set: { composition.router.selectTab($0) })
    }

    private var giftSheetBinding: Binding<GiftSheetRoute?> {
        Binding(get: { composition.router.giftSheet },
                set: { composition.router.giftSheet = $0 })
    }

    private var settingsBinding: Binding<Bool> {
        Binding(get: { composition.router.showsSettings },
                set: { if !$0 { composition.router.dismissSettings() } })
    }
}

/// Shared scroll container for a tab's root screen — content scrolls under the
/// floating glass tab bar, and the "Add a gift" pill is pinned just above it via
/// a bottom safe-area inset (so it never overlaps the bar on any device).
struct ScreenScroll<Content: View>: View {
    let composition: AppComposition
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color.bg)
        .floatingAddButton(composition: composition)
    }
}

/// The floating "Add a gift" button — a rounded-rect pill (Claude Design) pinned
/// just above the tab bar. Shared by `ScreenScroll` and Home's native List.
struct AddGiftFAB: View {
    let router: AppRouter

    var body: some View {
        Button { router.presentNewGift() } label: {
            Label("Add a gift", systemImage: "plus")
                .font(Font.app(16, .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(Color.ink))
                .ksCardShadow(strong: true)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .accessibilityLabel("Add a gift")
    }
}

extension View {
    /// Pin the floating "Add a gift" button above the tab bar.
    func floatingAddButton(composition: AppComposition) -> some View {
        safeAreaInset(edge: .bottom) { AddGiftFAB(router: composition.router) }
    }
}
