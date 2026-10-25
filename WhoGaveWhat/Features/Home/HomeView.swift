import SwiftUI

/// Home timeline as a native `List` — so swipe-to-delete and tap-to-open are the
/// system's own gestures (smooth, reliable) rather than a hand-rolled drag. Before the
/// first gift it shows `HomeWelcome` instead.
/// Shows the full timeline across all years, grouped by month; past years carry
/// their year in month headers and dates. The year summary lives in Insights.
struct HomeView: View {
    let composition: AppComposition

    var body: some View {
        let year = currentYear
        List {
            if composition.data.gifts.isEmpty {
                Section {
                    HomeWelcome(router: composition.router)
                        // The row spans the full width and pads itself, so the cell has room for the
                        // welcome tile's glow instead of clipping it.
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listSectionMargins(.horizontal, 0)
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
                                composition.deleteGift(id: gift.id, source: .home)
                            }
                        }
                    } header: {
                        monthHeader(group)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .readableColumn()
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(Color.appBackground)
        // The welcome card carries the only "Add a gift" action until the first gift.
        .floatingAddButton(composition: composition, isVisible: !composition.data.gifts.isEmpty)
        // The first saved gift and the last deleted one swap the welcome, timeline and button smoothly.
        .animation(.default, value: composition.data.gifts.isEmpty)
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

    private var timeline: [GiftTimelineSection] {
        composition.buildTimeline.execute(
            gifts: composition.data.gifts,
            filter: "all",
            relativeTo: composition.data.selfPerson?.id,
            displayYear: currentYear)
    }
}
