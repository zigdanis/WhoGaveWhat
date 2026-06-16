import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    private var filterOptions: [Segmented.Option] {
        [.init(key: "all", label: "All", accent: KS.ink),
         .init(key: "received", label: "Received", accent: KS.recv),
         .init(key: "given", label: "Given", accent: KS.ink)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary card
            Card {
                HStack(spacing: 0) {
                    summaryColumn(arrow: "↙", label: "Received", color: KS.recv,
                                  value: rub(store.sum(store.received)), count: store.received.count)
                    Rectangle().fill(KS.track).frame(width: 1).padding(.vertical, 2)
                    summaryColumn(arrow: "↗", label: "Given", color: KS.ink,
                                  value: rub(store.sum(store.given)), count: store.given.count)
                }
                .padding(.vertical, 18).padding(.horizontal, 6)
            }

            // Filter
            Segmented(options: filterOptions, selected: store.filter) { store.setFilter($0) }
                .padding(.top, 16)

            // Timeline groups
            ForEach(store.timeline) { group in
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(text: group.label)
                        .padding(.bottom, 7)
                    Card {
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, gift in
                                NavigationLink(value: gift.personId) {
                                    GiftRow(gift: gift)
                                }
                                .buttonStyle(.plain)
                                if idx < group.items.count - 1 { RowDivider().padding(.leading, 14) }
                            }
                        }
                    }
                }
                .padding(.top, 20)
            }
        }
        .padding(.horizontal, 16)
    }

    private func summaryColumn(arrow: String, label: String, color: Color, value: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(arrow).font(KS.font(15, .semibold))
                Text(LocalizedStringKey(label)).font(KS.font(13, .semibold))
            }
            .foregroundColor(color)
            Text(value).font(KS.font(23, .bold)).tracking(-0.3).foregroundColor(KS.ink).padding(.top, 8)
            Text(store.giftsCount(count)).font(KS.font(13, .regular)).foregroundColor(KS.muted).padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }
}
