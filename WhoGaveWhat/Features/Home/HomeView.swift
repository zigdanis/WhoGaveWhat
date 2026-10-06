import SwiftUI

/// Home timeline as a native `List` — so swipe-to-delete and tap-to-open are the
/// system's own gestures (smooth, reliable) rather than a hand-rolled drag.
struct HomeView: View {
    let composition: AppComposition
    /// Gift awaiting delete confirmation (set by the swipe action).
    @State private var pendingDelete: Gift?

    var body: some View {
        List {
            if timeline.isEmpty {
                Section {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 48, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(timeline) { group in
                    Section {
                        ForEach(group.gifts) { gift in
                            NavigationLink(value: gift) {
                                GiftRow(
                                    gift: gift,
                                    subtitle: composition.data.giftSubtitle(gift),
                                    dateLabel: gift.date.giftShortLabel(),
                                    currencyCode: composition.currencyCode)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    pendingDelete = gift
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Delete")
                            }
                        }
                    } header: {
                        Text(group.label)
                            .font(Font.app(13, .regular)).foregroundColor(Color.muted)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .floatingAddButton(composition: composition)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    composition.router.presentSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Settings")
            }
        }
        .confirmationDialog(
            "Delete this gift?",
            isPresented: deleteConfirmBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { gift in
            Button("Delete", role: .destructive) {
                composition.deleteGift(id: gift.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    /// Drives the confirmation dialog off the optional pending gift.
    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } })
    }

    /// Quiet placeholder shown before the first gift — a faint icon and a short
    /// explanation, with the shared floating add button remaining the only CTA.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gift")
                .font(.system(size: 46, weight: .light))
                .foregroundColor(Color.muted4)
            Text("No gifts yet")
                .font(Font.app(17, .semibold)).foregroundColor(Color.muted2)
            Text("Nothing here yet — add your first to start tracking.")
                .font(Font.app(14, .regular)).foregroundColor(Color.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
    }

    private var timeline: [GiftTimelineSection] {
        composition.buildTimeline.execute(gifts: composition.data.gifts, filter: "all")
    }
}
