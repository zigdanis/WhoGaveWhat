import Foundation

struct GiftTimelineSection: Identifiable, Equatable {
    let id: String
    let label: String
    let gifts: [Gift]
}

struct BuildGiftTimelineUseCase {
    func execute(gifts: [Gift], filter: String, locale: Locale = .current) -> [GiftTimelineSection] {
        let filtered = gifts
            .filter { filter == "all" || $0.direction.rawValue == filter }
            .sorted(by: Gift.newestFirst)
        let grouped = Dictionary(grouping: filtered) { $0.date.giftMonthLabel(locale: locale) }
        var seen = Set<String>()
        let labels = filtered.compactMap { gift -> String? in
            let label = gift.date.giftMonthLabel(locale: locale)
            return seen.insert(label).inserted ? label : nil
        }
        return labels.map { label in
            GiftTimelineSection(id: label, label: label, gifts: grouped[label] ?? [])
        }
    }
}
