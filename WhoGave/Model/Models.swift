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
