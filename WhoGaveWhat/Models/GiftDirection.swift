enum GiftDirection: String, Codable, CaseIterable, Hashable {
    case received
    case given
}

enum GiftDirectionResolver {
    static func resolve(
        giverID: String,
        recipientID: String,
        relativeTo personID: String
    ) -> GiftDirection? {
        if giverID == personID { return .given }
        if recipientID == personID { return .received }
        return nil
    }

    static func resolve(
        giverID: String,
        giverRole: PersonRole,
        recipientID: String,
        recipientRole: PersonRole
    ) -> GiftDirection {
        if giverRole == .household, recipientRole == .contact { return .given }
        if giverRole == .contact, recipientRole == .household { return .received }
        // Same-role gifts use "you" as the viewpoint, then deterministically fall back to received.
        if giverID == "you" { return .given }
        if recipientID == "you" { return .received }
        return .received
    }

    static func resolve(
        giverID: String,
        recipientID: String,
        householdIDs: Set<String>
    ) -> GiftDirection {
        resolve(
            giverID: giverID,
            giverRole: householdIDs.contains(giverID) ? .household : .contact,
            recipientID: recipientID,
            recipientRole: householdIDs.contains(recipientID) ? .household : .contact
        )
    }
}
