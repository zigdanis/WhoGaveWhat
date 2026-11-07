enum GiftEndpoint: Equatable {
    case giver
    case recipient
}

enum SwiftDataPersistenceError: Error, Equatable {
    case missingPerson(endpoint: GiftEndpoint, id: String)
    case identicalGiftEndpoints(id: String)
    /// A stored gift without a supported currency. Opening the store with `legacyGiftCurrency` gives
    /// gifts from before per-gift currencies one; a gift is never shown in a guessed currency.
    case missingCurrency(giftID: String)
}
