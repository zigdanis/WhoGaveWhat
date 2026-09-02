import Foundation
import Observation

@MainActor
@Observable
final class AddGiftState {
    var draft = AddGiftDraft()
    var picker: AddGiftPicker?
    var aiLoading = false

    private(set) var editingGiftID: String?
    private let suggestGift: SuggestGiftUseCase
    private var suggestionTask: Task<Void, Never>?

    init(route: GiftSheetRoute, data: AppData, suggestGift: SuggestGiftUseCase) {
        self.suggestGift = suggestGift
        editingGiftID = route.editingGiftID

        if let giftID = route.editingGiftID,
           let gift = data.gifts.first(where: { $0.id == giftID }) {
            draft = AddGiftDraft(
                name: gift.name,
                emoji: gift.emoji,
                value: Int(gift.value),
                valueTouched: true,
                fromID: gift.giverID,
                toID: gift.recipientID,
                paidByYou: gift.paidByYou,
                occasion: gift.occasion,
                date: gift.date,
                createdAt: gift.createdAt
            )
        }
    }

    var input: SaveGiftInput {
        SaveGiftInput(
            editingGiftID: editingGiftID,
            name: draft.name,
            emoji: draft.emoji,
            aiEmoji: draft.aiEmoji,
            value: draft.value,
            valueTouched: draft.valueTouched,
            fromID: draft.fromID,
            toID: draft.toID,
            paidByYou: draft.paidByYou,
            occasion: draft.occasion,
            date: draft.date,
            createdAt: draft.createdAt
        )
    }

    var effectiveEmoji: String {
        draft.emoji ?? draft.aiEmoji ?? suggestGift.instantSuggestion(for: draft.name).emoji
    }

    func direction(householdIDs: Set<String>, saveGift: SaveGiftUseCase) -> GiftDirection {
        saveGift.direction(for: input, householdIDs: householdIDs)
    }

    func setName(_ name: String) {
        draft.name = name
        draft.aiEmoji = nil
        suggestionTask?.cancel()
        aiLoading = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, suggestGift.isIntelligenceAvailable else { return }
        suggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled,
                  draft.name.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            aiLoading = true
            let result = await suggestGift.intelligentSuggestion(for: trimmed)
            guard !Task.isCancelled,
                  draft.name.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                aiLoading = false
                return
            }
            if let result {
                if draft.emoji == nil { draft.aiEmoji = result.emoji }
            }
            aiLoading = false
        }
    }

    func open(_ picker: AddGiftPicker) { self.picker = picker }
    func closePicker() { picker = nil }

    func selectFrom(_ id: String) {
        previewFrom(id)
        picker = nil
    }
    func selectTo(_ id: String) { previewTo(id); picker = nil }
    func previewFrom(_ id: String) { draft.fromID = id }
    func previewTo(_ id: String) { draft.toID = id }
    func selectOccasion(_ occasion: String) {
        let occasion = occasion.trimmingCharacters(in: .whitespaces)
        guard !occasion.isEmpty else { return }
        draft.occasion = occasion
        picker = nil
    }
    func selectEmoji(_ emoji: String) { draft.emoji = emoji; picker = nil }
    func selectDate(_ date: Date) { draft.date = date; picker = nil }

    func useCustomEmoji(_ value: String) {
        let emoji = value.firstGrapheme
        guard !emoji.isEmpty else { return }
        selectEmoji(emoji)
    }

    func save(using composition: AppComposition) {
        guard input.canSave else { return }
        composition.saveGift(input)
        if editingGiftID == nil { composition.router.selectTab(.home) }
        composition.router.dismissGiftSheet()
    }

    func cancel() {
        suggestionTask?.cancel()
        aiLoading = false
    }
}
