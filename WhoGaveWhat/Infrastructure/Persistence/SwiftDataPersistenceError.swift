enum GiftEndpoint: Equatable {
    case giver
    case recipient
}

enum SwiftDataPersistenceError: Error, Equatable {
    case missingPerson(endpoint: GiftEndpoint, id: String)
    case identicalGiftEndpoints(id: String)
}
