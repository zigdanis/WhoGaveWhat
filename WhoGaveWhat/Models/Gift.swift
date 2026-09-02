import Foundation

struct Gift: Identifiable, Hashable {
    let id: String
    var emoji: String
    var name: String
    var direction: GiftDirection
    var giverID: String
    var recipientID: String
    var paidByYou: Bool
    var occasion: String
    var date: Date
    var value: Double
    let createdAt: Date

    /// Newest date first, then newest creation order within the same day.
    static func newestFirst(_ lhs: Gift, _ rhs: Gift) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id > rhs.id
    }
}
