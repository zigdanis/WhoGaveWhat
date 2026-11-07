import Foundation

struct SaveGiftInput: Equatable {
    var editingGiftID: String?
    var name: String
    var emoji: String?
    var aiEmoji: String?
    var value: Int?
    var valueTouched: Bool
    var estimatedValue: Int?
    /// The currency `estimatedValue` was asked for; nil means `currency`.
    var estimatedCurrency: SupportedCurrency?
    /// The currency of the gift's value: the default currency for a new gift unless the user picked another.
    var currency: SupportedCurrency
    var fromID: String?
    var toID: String?
    var paidByYou: Bool
    var occasion: String?
    var date: Date
    var createdAt: Date?

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && fromID != nil
            && toID != nil
            && fromID != toID
    }
}

@MainActor
struct SaveGiftUseCase {
    let giftGateway: GiftGateway
    let suggestGift: SuggestGiftUseCase
    /// The clock behind `createdAt` of new gifts and `lastSavedAt` of every save.
    var now: () -> Date = { Date() }

    @discardableResult
    func execute(_ input: SaveGiftInput) throws -> Gift? {
        guard input.canSave, let fromID = input.fromID, let toID = input.toID else {
            return nil
        }

        let suggestion = suggestGift.instantSuggestion(for: input.name)
        let savedAt = now()
        // By design an untouched estimate is saved as the gift's value, so gifts get approximate
        // amounts instead of 0. Once the user edits the field, their value (even empty = 0) wins.
        // An estimate keeps the currency it was asked for.
        let usesEstimate = !input.valueTouched && input.estimatedValue != nil
        let value = input.valueTouched ? (input.value ?? 0) : (input.estimatedValue ?? 0)
        let currency = usesEstimate ? (input.estimatedCurrency ?? input.currency) : input.currency
        let gift = Gift(
            id: input.editingGiftID ?? "g\(UUID().uuidString)",
            emoji: input.emoji ?? input.aiEmoji ?? suggestion.emoji,
            name: input.name.trimmingCharacters(in: .whitespaces),
            giverID: fromID,
            recipientID: toID,
            paidByYou: input.paidByYou,
            occasion: input.occasion ?? "Just because",
            date: input.date,
            value: Double(value),
            currency: currency,
            createdAt: input.createdAt ?? savedAt,
            emojiPickedByUser: input.emoji != nil,
            lastSavedAt: savedAt
        )
        try giftGateway.save(gift)
        return gift
    }
}
