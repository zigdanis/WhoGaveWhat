enum GiftDirection: String, Codable, CaseIterable, Hashable {
    case received
    case given
}

enum GiftDirectionResolver {
    /// Direction of a gift as seen by `personID`, or nil when that person is neither endpoint.
    static func resolve(
        giverID: String,
        recipientID: String,
        relativeTo personID: String
    ) -> GiftDirection? {
        if giverID == personID { return .given }
        if recipientID == personID { return .received }
        return nil
    }
}
