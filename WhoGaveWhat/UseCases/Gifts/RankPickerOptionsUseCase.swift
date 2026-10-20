import Foundation

/// The side of a gift a person is picked for.
enum PersonPickerRole {
    case giver
    case recipient
}

/// Orders picker options by how recently, then how often, they were saved in a gift in that role.
/// Options never used in the role follow in their given order.
struct RankPickerOptionsUseCase {
    func rankPeople(_ people: [Person], by role: PersonPickerRole, in gifts: [Gift]) -> [Person] {
        let usageByID = usageByKey(of: gifts) { role == .giver ? $0.giverID : $0.recipientID }
        return rank(people) { usageByID[$0.id] }
    }

    func rankOccasions(_ occasions: [Occasion], in gifts: [Gift]) -> [Occasion] {
        let usageByName = usageByKey(of: gifts) { $0.occasion }
        return rank(occasions) { usageByName[$0.name] }
    }

    private struct Usage {
        var latest: Date
        var count: Int
    }

    private func usageByKey(of gifts: [Gift], key keyOf: (Gift) -> String) -> [String: Usage] {
        var result: [String: Usage] = [:]
        for gift in gifts {
            let key = keyOf(gift)
            guard !key.isEmpty else { continue }
            if var existing = result[key] {
                existing.latest = max(existing.latest, gift.lastUsedAt)
                existing.count += 1
                result[key] = existing
            } else {
                result[key] = Usage(latest: gift.lastUsedAt, count: 1)
            }
        }
        return result
    }

    private func rank<Element>(_ elements: [Element], lookup: (Element) -> Usage?) -> [Element] {
        var used: [(index: Int, element: Element, usage: Usage)] = []
        var unused: [Element] = []
        for (index, element) in elements.enumerated() {
            if let usage = lookup(element) {
                used.append((index: index, element: element, usage: usage))
            } else {
                unused.append(element)
            }
        }
        used.sort { lhs, rhs in
            if lhs.usage.latest != rhs.usage.latest { return lhs.usage.latest > rhs.usage.latest }
            if lhs.usage.count != rhs.usage.count { return lhs.usage.count > rhs.usage.count }
            return lhs.index < rhs.index
        }
        return used.map(\.element) + unused
    }
}
