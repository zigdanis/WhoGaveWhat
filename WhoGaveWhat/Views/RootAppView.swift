import SwiftUI

/// Native iOS 26 shell: a Liquid Glass tab bar floating over three navigation
/// stacks, with a floating "Add a gift" pill pinned just above it. Person detail
/// is a native push; "Add a gift" and Settings are native sheets.
struct RootAppView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView(selection: tabSelection) {
            stack(.home, "Home", "house") {
                // Home is its own native List (smooth swipe-to-delete), so it
                // carries its own background + floating button rather than the
                // shared ScreenScroll wrapper.
                HomeView()
                    .navigationTitle("Who Gave What")
                    .toolbar { settingsButton }
            }
            stack(.people, "People", "person.2") {
                ScreenScroll { PeopleView() }
                    .navigationTitle("People")
            }
            stack(.insights, "Insights", "chart.bar.xaxis") {
                ScreenScroll { InsightsView() }
                    .navigationTitle("Insights")
            }
        }
        .tint(KS.recv)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: sheetBinding) { AddGiftSheet() }
        .sheet(isPresented: settingsBinding) { SettingsView() }
    }

    /// One tab: a navigation stack that pushes `PersonDetailView` for any entity id.
    @ViewBuilder
    private func stack<Content: View>(_ value: Tab, _ title: String, _ icon: String,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: String.self) { id in
                    PersonDetailView(entityId: id)
                }
                .navigationDestination(for: Gift.self) { gift in
                    GiftDetailView(giftId: gift.id)
                }
        }
        .tabItem { Label(LocalizedStringKey(title), systemImage: icon) }
        .tag(value)
    }

    @ToolbarContentBuilder
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { store.openSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(KS.ink)
            }
            .accessibilityLabel("Settings")
        }
    }

    private var tabSelection: Binding<Tab> {
        Binding(get: { store.tab }, set: { store.setTab($0) })
    }

    private var sheetBinding: Binding<Bool> {
        Binding(get: { store.sheetOpen }, set: { if !$0 { store.closeSheet() } })
    }

    private var settingsBinding: Binding<Bool> {
        Binding(get: { store.showSettings }, set: { if !$0 { store.closeSettings() } })
    }
}

/// Shared scroll container for a tab's root screen — content scrolls under the
/// floating glass tab bar, and the "Add a gift" pill is pinned just above it via
/// a bottom safe-area inset (so it never overlaps the bar on any device).
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .background(KS.bg)
        .floatingAddButton()
    }
}

/// The floating "Add a gift" button — a rounded-rect pill (Claude Design) pinned
/// just above the tab bar. Shared by `ScreenScroll` and Home's native List.
struct AddGiftFAB: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Button { store.openSheet() } label: {
            Label("Add a gift", systemImage: "plus")
                .font(KS.font(16, .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.ink))
                .ksCardShadow(strong: true)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .accessibilityLabel("Add a gift")
    }
}

extension View {
    /// Pin the floating "Add a gift" button above the tab bar.
    func floatingAddButton() -> some View {
        safeAreaInset(edge: .bottom) { AddGiftFAB() }
    }
}
