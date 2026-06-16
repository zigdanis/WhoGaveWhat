import SwiftUI

enum Flow: String, Codable, CaseIterable {
    case received
    case given
}

/// Family members (the household: You, wife, daughters).
struct Member: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
}

/// People outside the household you give to / get from.
struct Person: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
}

struct Gift: Identifiable, Hashable {
    var id: String
    var emoji: String
    var name: String
    var flow: Flow
    var personId: String
    var memberId: String
    var paidByYou: Bool
    var celebration: String
    var date: Date
    var value: Double

    /// Creation order, recovered from the id (`g<milliseconds>` for real gifts,
    /// `g1`, `g2`… for the seed). Used as a tiebreaker so that, within a single
    /// day, a gift created later sorts above one created earlier.
    var creationSeq: Int64 {
        let digits = id.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int64(digits) ?? 0
    }
}

extension Gift {
    /// Newest first, then by creation time within the same calendar day so a gift
    /// added later that day rises to the top (see `creationSeq`).
    static func newestFirst(_ a: Gift, _ b: Gift) -> Bool {
        if a.date != b.date { return a.date > b.date }
        return a.creationSeq > b.creationSeq
    }
}

/// Auto-suggestion entry: keywords → emoji + guessed value.
struct Suggestion {
    let keywords: [String]
    let emoji: String
    let value: Double
}

/// Visual identity for a flow direction.
struct FlowMeta {
    let main: Color
    let deep: Color
    let tint: Color
    let label: String
    let arrow: String   // ↙ received / ↗ given
}
