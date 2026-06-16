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

            // Timeline groups — or an empty placeholder when nothing matches.
            if store.timeline.isEmpty {
                emptyState.padding(.top, 64)
            } else {
                ForEach(store.timeline) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(text: group.label)
                            .padding(.bottom, 7)
                        Card {
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, gift in
                                    SwipeToDelete(onDelete: { store.deleteGift(gift.id) }) {
                                        NavigationLink(value: gift) {
                                            GiftRow(gift: gift)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    if idx < group.items.count - 1 { RowDivider().padding(.leading, 14) }
                                }
                            }
                        }
                    }
                    .padding(.top, 20)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Quiet placeholder shown when the current filter has no gifts — a faint
    /// icon plus a coloured text button to add the first record.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gift")
                .font(.system(size: 46, weight: .light))
                .foregroundColor(KS.muted4)
            Text("No gifts yet")
                .font(KS.font(17, .semibold)).foregroundColor(KS.muted2)
            Text("Nothing here yet — add your first to start tracking.")
                .font(KS.font(14, .regular)).foregroundColor(KS.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button { store.openSheet() } label: {
                Text("Add your first gift")
                    .font(KS.font(15, .semibold)).foregroundColor(KS.emerald)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
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
