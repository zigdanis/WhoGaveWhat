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
    private let debounce: Duration
    private(set) var suggestionTask: Task<Void, Never>?
    /// The automatically chosen emoji a gift being edited already has; kept until a rename yields a better guess.
    private var storedEmoji: String?

    init(
        route: GiftSheetRoute,
        data: AppData,
        suggestGift: SuggestGiftUseCase,
        debounce: Duration = .milliseconds(500)
    ) {
        self.suggestGift = suggestGift
        self.debounce = debounce
        editingGiftID = route.editingGiftID

        if let giftID = route.editingGiftID,
            let gift = data.gifts.first(where: { $0.id == giftID })
        {
            // An emoji the user picked stays sticky; an inferred one is re-inferred on rename.
            draft = AddGiftDraft(
                name: gift.name,
                emoji: gift.emojiPickedByUser ? gift.emoji : nil,
                value: Int(gift.value),
                valueTouched: true,
                fromID: gift.giverID,
                toID: gift.recipientID,
                paidByYou: gift.paidByYou,
                occasion: gift.occasion,
                date: gift.date,
                createdAt: gift.createdAt,
                aiEmoji: gift.emojiPickedByUser ? nil : gift.emoji
            )
            if !gift.emojiPickedByUser { storedEmoji = gift.emoji }
        }
    }

    /// Loads the on-device model while the sheet opens so the first inference is fast.
    func prewarm() {
        guard suggestGift.isIntelligenceAvailable else { return }
        suggestGift.prewarmIntelligence()
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

    var name: String {
        get { draft.name }
        set { setName(newValue) }
    }

    var valueText: String {
        get {
            guard draft.valueTouched else { return "" }
            return draft.value.map(String.init) ?? ""
        }
        set {
            let digits = newValue.filter(\.isNumber)
            draft.value = digits.isEmpty ? nil : Int(digits)
            draft.valueTouched = true
        }
    }

    func direction(relativeTo selfPersonID: String?) -> GiftDirection? {
        guard let selfPersonID, let fromID = input.fromID, let toID = input.toID else { return nil }
        return GiftDirectionResolver.resolve(
            giverID: fromID,
            recipientID: toID,
            relativeTo: selfPersonID
        )
    }

    /// Updates the name, shows the keyword heuristic right away and, after a short
    /// pause in typing, asks the on-device model for a better emoji.
    func setName(_ name: String) {
        guard name != draft.name else { return }
        draft.name = name
        // Without a specific keyword match, keep the emoji the gift already had instead of the generic one.
        draft.aiEmoji = suggestGift.keywordSuggestion(for: name) == nil ? storedEmoji : nil
        suggestionTask?.cancel()
        suggestionTask = nil
        aiLoading = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.emoji == nil, trimmed.count >= 2, suggestGift.isIntelligenceAvailable else {
            return
        }
        suggestionTask = Task {
            try? await Task.sleep(for: debounce)
            guard !isStale(trimmed) else { return }
            aiLoading = true
            let result = await suggestGift.intelligentSuggestion(for: trimmed)
            guard !isStale(trimmed) else { return }
            aiLoading = false
            if let result, draft.emoji == nil { draft.aiEmoji = result.emoji }
        }
    }

    /// True once this inference was cancelled or the name moved on. Whoever cancelled it
    /// already reset `aiLoading` or started the newer inference that now owns it.
    private func isStale(_ trimmedName: String) -> Bool {
        Task.isCancelled
            || draft.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
    }

    func open(_ picker: AddGiftPicker) { self.picker = picker }
    func closePicker() { picker = nil }

    func selectFrom(_ id: String) {
        previewFrom(id)
        picker = nil
    }
    func selectTo(_ id: String) { previewTo(id); picker = nil }
    func previewFrom(_ id: String?) { draft.fromID = id }
    func previewTo(_ id: String?) { draft.toID = id }
    func selectOccasion(_ occasion: String) {
        let occasion = occasion.trimmingCharacters(in: .whitespaces)
        guard !occasion.isEmpty else { return }
        draft.occasion = occasion
        picker = nil
    }
    func selectEmoji(_ emoji: String) {
        draft.emoji = emoji
        suggestionTask?.cancel()
        suggestionTask = nil
        aiLoading = false
        picker = nil
    }
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
        suggestionTask = nil
        aiLoading = false
    }
}
