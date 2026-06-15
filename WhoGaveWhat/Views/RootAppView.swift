import SwiftUI

/// Native iOS 26 shell: a Liquid Glass tab bar floating over three navigation
/// stacks. Person detail is a native push; "Add a gift" is a native sheet.
struct RootAppView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView(selection: tabSelection) {
            stack(.home, "Home", "house") {
                ScreenScroll { HomeView() }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { addButton }
            }
            stack(.people, "People", "person.2") {
                ScreenScroll { PeopleView() }
                    .navigationTitle("People")
                    .toolbar { addButton }
            }
            stack(.insights, "Insights", "chart.bar") {
                ScreenScroll { InsightsView() }
                    .navigationTitle("Insights")
            }
        }
        .tint(KS.give)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: sheetBinding) {
            AddGiftSheet()
        }
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
        }
        .tabItem { Label(title, systemImage: icon) }
        .tag(value)
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { store.openSheet() } label: {
                Image(systemName: "plus").fontWeight(.semibold)
            }
            .tint(KS.give)
            .accessibilityLabel("Add a gift")
        }
    }

    private var tabSelection: Binding<Tab> {
        Binding(get: { store.tab }, set: { store.setTab($0) })
    }

    private var sheetBinding: Binding<Bool> {
        Binding(get: { store.sheetOpen }, set: { if !$0 { store.closeSheet() } })
    }
}

/// Shared scroll container for a tab's root screen — content scrolls under the
/// floating glass tab bar, which insets the bottom automatically.
private struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.top, 4)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(KS.bg)
    }
}
