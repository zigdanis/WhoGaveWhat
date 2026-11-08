import Foundation

/// Gives a saved gift the icon its inference returned after the gift sheet closed. The answer is dropped
/// when it no longer fits: the gift was deleted or renamed since, or the user picked its icon by hand.
@MainActor
struct ApplyLateGiftIconUseCase {
    let giftGateway: GiftGateway

    /// Says whether the gift was changed. `requestedName` is the trimmed name the icon was asked for.
    @discardableResult
    func execute(emoji: String, giftID: String, requestedName: String, gifts: [Gift]) throws -> Bool {
        guard var gift = gifts.first(where: { $0.id == giftID }),
            !gift.emojiPickedByUser,
            gift.name.trimmingCharacters(in: .whitespacesAndNewlines) == requestedName,
            gift.emoji != emoji
        else { return false }
        gift.emoji = emoji
        // The user did not touch the gift, so `lastSavedAt` (its last use) stays as it was.
        try giftGateway.save(gift)
        return true
    }
}
