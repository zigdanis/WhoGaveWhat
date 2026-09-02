import Foundation

struct SaveGiftInput: Equatable {
    var editingGiftID: String?
    var name: String
    var emoji: String?
    var aiEmoji: String?
    var value: Int?
    var valueTouched: Bool
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

    func direction(for input: SaveGiftInput, householdIDs: Set<String>) -> GiftDirection {
        GiftDirectionResolver.resolve(
            giverID: input.fromID ?? "",
            recipientID: input.toID ?? "",
            householdIDs: householdIDs
        )
    }

    @discardableResult
    func execute(_ input: SaveGiftInput, householdIDs: Set<String>) throws -> Gift? {
        guard input.canSave, let fromID = input.fromID, let toID = input.toID else {
            return nil
        }

        let suggestion = suggestGift.instantSuggestion(for: input.name)
        let direction = direction(for: input, householdIDs: householdIDs)
        let gift = Gift(
            id: input.editingGiftID ?? "g\(UUID().uuidString)",
            emoji: input.emoji ?? input.aiEmoji ?? suggestion.emoji,
            name: input.name.trimmingCharacters(in: .whitespaces),
            direction: direction,
            giverID: fromID,
            recipientID: toID,
            paidByYou: input.paidByYou,
            occasion: input.occasion ?? "Just because",
            date: input.date,
            value: input.valueTouched ? Double(input.value ?? 0) : 0,
            createdAt: input.createdAt ?? Date()
        )
        try giftGateway.save(gift)
        return gift
    }
}
