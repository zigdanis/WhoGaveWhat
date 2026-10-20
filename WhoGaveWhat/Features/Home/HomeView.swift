import SwiftUI

/// Home timeline as a native `List` — so swipe-to-delete and tap-to-open are the
/// system's own gestures (smooth, reliable) rather than a hand-rolled drag.
/// Shows the full timeline across all years, grouped by month; past years carry
/// their year in month headers and dates. The year summary lives in Insights.
struct HomeView: View {
    let composition: AppComposition

    var body: some View {
        let year = currentYear
        List {
            if composition.data.gifts.isEmpty {
                Section {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
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
                                    dateLabel: gift.date.giftShortLabel(displayYear: year),
                                    currencyCode: composition.currencyCode)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                            .swipeToDelete(title: Text("Delete this gift?"), allowsFullSwipe: true) {
                                composition.deleteGift(id: gift.id)
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
    }

    /// Months and dates omit the year only for the current calendar year.
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
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

    private var timeline: [GiftTimelineSection] {
        composition.buildTimeline.execute(
            gifts: composition.data.gifts,
            filter: "all",
            relativeTo: composition.data.selfPerson?.id,
            displayYear: currentYear)
    }
}
