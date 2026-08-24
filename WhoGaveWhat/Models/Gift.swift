import Foundation

struct Gift: Identifiable, Hashable {
    var id: String
    var emoji: String
    var name: String
    var flow: GiftFlow
    var personId: String
    var memberId: String
    var paidByYou: Bool
    var celebration: String
    var date: Date
    var value: Double

    /// Creation order recovered from ids such as `g1750000000000`.
    var creationSeq: Int64 {
        let digits = id.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int64(digits) ?? 0
    }

    /// Newest date first, then newest creation order within the same day.
    static func newestFirst(_ lhs: Gift, _ rhs: Gift) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.creationSeq > rhs.creationSeq
    }
}
