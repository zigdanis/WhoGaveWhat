import SwiftUI

/// Home timeline as a native `List` — so swipe-to-delete and tap-to-open are the
/// system's own gestures (smooth, reliable) rather than a hand-rolled drag. The
/// summary card and filter ride along as plain, separator-less rows on top.
struct HomeView: View {
    @EnvironmentObject var store: AppStore
    /// Gift awaiting delete confirmation (set by the swipe action).
    @State private var pendingDelete: Gift?

    private var filterOptions: [Segmented.Option] {
        [.init(key: "all", label: "All", accent: KS.ink),
         .init(key: "received", label: "Received", accent: KS.recv),
         .init(key: "given", label: "Given", accent: KS.ink)]
    }

    var body: some View {
        List {
            // Summary + filter — quiet rows with no card chrome of their own.
            Section {
                summaryCard
                Segmented(options: filterOptions, selected: store.filter) { store.setFilter($0) }
                    .padding(.top, 4)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if store.timeline.isEmpty {
                Section {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 48, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(store.timeline) { group in
                    Section {
                        ForEach(group.items) { gift in
                            NavigationLink(value: gift) { GiftRow(gift: gift) }
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { pendingDelete = gift } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("Delete")
                                }
                        }
                    } header: {
                        Text(group.label)
                            .font(KS.font(13, .regular)).foregroundColor(KS.muted)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(KS.bg)
        .floatingAddButton()
        .confirmationDialog("Delete this gift?",
                            isPresented: deleteConfirmBinding,
                            titleVisibility: .visible,
                            presenting: pendingDelete) { gift in
            Button("Delete", role: .destructive) {
                store.deleteGift(gift.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    /// Drives the confirmation dialog off the optional pending gift.
    private var deleteConfirmBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: Summary

    private var summaryCard: some View {
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
