import SwiftUI

struct RootAppView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            // Scrollable content
            ScrollView {
                Group {
                    switch store.tab {
                    case .home:     HomeView()
                    case .people:   PeopleView()
                    case .insights: InsightsView()
                    }
                }
                .id(store.tab)
                .transition(.opacity)
                .padding(.top, 54)
                .padding(.bottom, 128)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)

            // FAB
            if showFab {
                Button { store.openSheet() } label: {
                    HStack(spacing: 8) {
                        Text("+").font(KS.font(26, .medium)).padding(.top, -2)
                        Text("Add a gift").font(KS.font(16, .heavy))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .background(Capsule().fill(KS.give))
                    .shadow(color: KS.give.opacity(0.4), radius: 15, x: 0, y: 14)
                }
                .padding(.bottom, 94)
                .transition(.scale.combined(with: .opacity))
            }

            // Tab bar
            TabBar()
        }
        .animation(.easeInOut(duration: 0.2), value: store.tab)
        .animation(.easeInOut(duration: 0.2), value: showFab)
        .overlay {
            // Person detail
            if let id = store.detailId {
                PersonDetailView(entityId: id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .overlay {
            // Add gift sheet
            if store.sheetOpen {
                AddGiftSheet()
                    .zIndex(40)
            }
        }
    }

    private var showFab: Bool {
        (store.tab == .home || store.tab == .people) && store.detailId == nil && !store.sheetOpen
    }
}

// MARK: - Bottom tab bar

private struct TabBar: View {
    @EnvironmentObject var store: AppStore

    private let tabs: [(Tab, String, String)] = [
        (.home, "house.fill", "Home"),
        (.people, "person.2.fill", "People"),
        (.insights, "chart.bar.fill", "Insights"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab, icon, label in
                let sel = store.tab == tab
                Button { store.setTab(tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon)
                            .font(.system(size: 23, weight: sel ? .semibold : .regular))
                            .symbolRenderingMode(.monochrome)
                            .environment(\.symbolVariants, sel ? .fill : .none)
                        Text(label).font(KS.font(11, .heavy))
                    }
                    .foregroundColor(sel ? KS.give : Color(hex: 0xB5AA9E))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(
            KS.bg.opacity(0.86)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color(hex: 0xEEE5DB)).frame(height: 1), alignment: .top)
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
