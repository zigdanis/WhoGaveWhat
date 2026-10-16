import Foundation

struct GiftTimelineSection: Identifiable, Equatable {
    let id: String
    let label: String
    let gifts: [Gift]

    var total: Double { gifts.totalValue }
}

struct BuildGiftTimelineUseCase {
    func execute(
        gifts: [Gift],
        filter: String,
        relativeTo selfPersonID: String?,
        displayYear: Int? = nil,
        locale: Locale = .current
    ) -> [GiftTimelineSection] {
        let filtered =
            gifts
            .filter { filter == "all" || $0.direction(relativeTo: selfPersonID)?.rawValue == filter }
            .sorted(by: Gift.newestFirst)
        let grouped = Dictionary(grouping: filtered) { $0.date.giftMonthLabel(displayYear: displayYear, locale: locale) }
        var seen = Set<String>()
        let labels = filtered.compactMap { gift -> String? in
            let label = gift.date.giftMonthLabel(displayYear: displayYear, locale: locale)
            return seen.insert(label).inserted ? label : nil
        }
        return labels.map { label in
            GiftTimelineSection(id: label, label: label, gifts: grouped[label] ?? [])
        }
    }
}
