/// What a gift save actually did, so a screen can tell an attempt from its outcome.
enum GiftSaveResult: Equatable {
    case saved
    /// The input was incomplete, so nothing was attempted.
    case invalid
    /// The store refused the write and rolled it back; the draft can be saved again.
    case failed
}

/// What a deletion actually did. After `failed` the record and everything tied to it are still stored.
enum DeletionResult: Equatable {
    case deleted
    case failed
}
