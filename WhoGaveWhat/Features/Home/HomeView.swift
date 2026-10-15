import SwiftUI

/// Home timeline as a native `List` — so swipe-to-delete and tap-to-open are the
/// system's own gestures (smooth, reliable) rather than a hand-rolled drag.
/// A title and the year summary sit above the month sections.
struct HomeView: View {
    let composition: AppComposition
    /// Gift awaiting delete confirmation (set by the swipe action).
    @State private var pendingDelete: Gift?
    /// Year chosen in the menu; nil follows the default (current year, else the latest with gifts).
    @State private var selectedYear: Int?

    var body: some View {
        let year = displayedYear
        List {
            Section {
                header(year: year)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if composition.data.gifts.isEmpty {
                Section {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(timeline(year: year)) { group in
                    Section {
                        ForEach(group.gifts) { gift in
                            NavigationLink(value: gift) {
                                GiftRow(
                                    gift: gift,
                                    subtitle: composition.data.giftSubtitle(gift),
                                    dateLabel: gift.date.giftShortLabel(displayYear: year),
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
                        monthHeader(group)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(Color.appBackground)
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

    private var displayedYear: Int {
        composition.buildInsights.resolvedYear(selected: selectedYear, gifts: composition.data.gifts)
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { displayedYear },
            set: { selectedYear = $0 })
    }

    private func header(year: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Who gave what")
                .font(Font.app(28, .bold)).foregroundColor(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !composition.data.gifts.isEmpty {
                YearSummaryCard(
                    summary: composition.buildInsights.summary(
                        gifts: composition.data.gifts,
                        relativeTo: composition.data.selfPersonID,
                        year: year),
                    hasViewpoint: composition.data.selfPersonID != nil,
                    currencyCode: composition.currencyCode,
                    years: composition.buildInsights.availableYears(gifts: composition.data.gifts),
                    selectedYear: yearBinding,
                    onMarkSelf: { composition.router.selectTab(.people) })
            }
        }
    }

    /// Month name with that month's total.
    private func monthHeader(_ group: GiftTimelineSection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.label)
                .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
            Spacer(minLength: 8)
            Text(formattedCurrency(group.total, code: composition.currencyCode))
                .font(Font.app(13, .semibold, rounded: true)).foregroundColor(Color.textSecondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Quiet placeholder shown before the first gift — a faint icon and a short
    /// explanation, with the shared floating add button remaining the only CTA.
    private var emptyState: some View {
        Card {
            VStack(spacing: 12) {
                Image(systemName: "gift")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Color.textTertiary)
                Text("No gifts yet")
                    .font(Font.app(17, .semibold)).foregroundColor(Color.textPrimary)
                Text("Nothing here yet — add your first to start tracking.")
                    .font(Font.app(14, .regular)).foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 16)
        }
    }

    private func timeline(year: Int) -> [GiftTimelineSection] {
        composition.buildTimeline.execute(
            gifts: composition.buildInsights.gifts(composition.data.gifts, in: year),
            filter: "all",
            relativeTo: composition.data.selfPersonID,
            displayYear: year)
    }
}
