import Foundation

struct SaveGiftInput: Equatable {
    var editingGiftID: String?
    var name: String
    var emoji: String?
    var aiEmoji: String?
    var value: Int?
    var aiValue: Double?
    var valueTouched: Bool
    var fromID: String?
    var toID: String?
    var paidByYou: Bool
    var celebration: String?
    var date: Date

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

    func flow(for input: SaveGiftInput, householdIDs: Set<String>) -> GiftFlow {
        let fromHousehold = input.fromID.map(householdIDs.contains) ?? false
        let toHousehold = input.toID.map(householdIDs.contains) ?? false
        if toHousehold && !fromHousehold { return .received }
        if fromHousehold && !toHousehold { return .given }
        if input.fromID == "you" { return .given }
        if input.toID == "you" { return .received }
        return .received
    }

    @discardableResult
    func execute(_ input: SaveGiftInput, householdIDs: Set<String>) throws -> Gift? {
        guard input.canSave, let fromID = input.fromID, let toID = input.toID else {
            return nil
        }

        let suggestion = suggestGift.instantSuggestion(for: input.name)
        let flow = flow(for: input, householdIDs: householdIDs)
        let memberID = flow == .received ? toID : fromID
        let personID = flow == .received ? fromID : toID
        let gift = Gift(
            id: input.editingGiftID ?? "g\(Int(Date().timeIntervalSince1970 * 1_000))",
            emoji: input.emoji ?? input.aiEmoji ?? suggestion.emoji,
            name: input.name.trimmingCharacters(in: .whitespaces),
            flow: flow,
            personId: personID,
            memberId: memberID,
            paidByYou: fromID == "you" || input.paidByYou,
            celebration: input.celebration ?? "Just because",
            date: input.date,
            value: input.valueTouched ? Double(input.value ?? 0) : (input.aiValue ?? suggestion.value)
        )
        try giftGateway.save(gift)
        return gift
    }
}
