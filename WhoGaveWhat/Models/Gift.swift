import Foundation

struct Gift: Identifiable, Hashable {
    let id: String
    var emoji: String
    var name: String
    var giverID: String
    var recipientID: String
    var paidByYou: Bool
    var occasion: String
    var date: Date
    var value: Double
    let createdAt: Date
    /// True when the user chose the emoji in the picker rather than inferring it from the name.
    var emojiPickedByUser = false

    /// Direction as seen by the viewpoint person, or nil without a viewpoint or when it isn't an endpoint.
    func direction(relativeTo personID: String?) -> GiftDirection? {
        guard let personID else { return nil }
        return GiftDirectionResolver.resolve(
            giverID: giverID,
            recipientID: recipientID,
            relativeTo: personID
        )
    }

    /// Newest date first, then newest creation order within the same day.
    static func newestFirst(_ lhs: Gift, _ rhs: Gift) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id > rhs.id
    }
}
