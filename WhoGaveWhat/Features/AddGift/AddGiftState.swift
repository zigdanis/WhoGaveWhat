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
    private let preferences: PreferencesGateway?
    private let analytics: AnalyticsGateway
    /// Applies a cloud icon choice through the composition root, which records and publishes it.
    private let applyCloudIconConsent: ((CloudIconConsent) -> Void)?
    private var hasEditedName = false
    private(set) var suggestionTask: Task<Void, Never>?
    /// The automatically chosen emoji a gift being edited already has; kept until a rename yields a better guess.
    private var storedEmoji: String?

    init(
        route: GiftSheetRoute,
        data: AppData,
        suggestGift: SuggestGiftUseCase,
        preferences: PreferencesGateway? = nil,
        debounce: Duration = .milliseconds(500),
        analytics: AnalyticsGateway = NoopAnalyticsGateway(),
        applyCloudIconConsent: ((CloudIconConsent) -> Void)? = nil
    ) {
        self.suggestGift = suggestGift
        self.preferences = preferences
        self.debounce = debounce
        self.analytics = analytics
        self.applyCloudIconConsent = applyCloudIconConsent
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

    /// Loads the selected model while the sheet opens so the first inference is fast.
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
            estimatedValue: draft.estimatedValue,
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

    var showsCloudIconConsent: Bool {
        hasEditedName && preferences?.cloudIconConsent == .undecided && draft.emoji == nil
            && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    func allowCloudIcons() {
        setCloudIconConsent(.allowed)
        scheduleSuggestion(after: .zero)
    }

    func declineCloudIcons() {
        setCloudIconConsent(.declined)
        // Any in-flight inference belongs to the old routing choice.
        scheduleSuggestion(after: debounce)
    }

    private func setCloudIconConsent(_ consent: CloudIconConsent) {
        if let applyCloudIconConsent {
            applyCloudIconConsent(consent)
        } else {
            preferences?.setCloudIconConsent(consent)
            analytics.track(.cloudIconsConsentChanged(allowed: consent == .allowed, source: .addGift))
        }
    }

    var name: String {
        get { draft.name }
        set { setName(newValue) }
    }

    /// True while the shown value is the inferred estimate rather than something the user entered.
    var showsEstimate: Bool { !draft.valueTouched && draft.estimatedValue != nil }

    /// The value the gift would be saved with, if any: the user's, or else the estimate.
    var effectiveValue: Int? { draft.valueTouched ? draft.value : draft.estimatedValue }

    var valueText: String {
        get {
            if showsEstimate { return draft.estimatedValue.map(String.init) ?? "" }
            guard draft.valueTouched else { return "" }
            return draft.value.map(String.init) ?? ""
        }
        set {
            let digits = newValue.filter(\.isNumber)
            // The first edit says whether the user overrode an estimate or typed from scratch.
            if !draft.valueTouched {
                analytics.track(.giftPriceEdited(hadEstimate: draft.estimatedValue != nil))
            }
            draft.value = digits.isEmpty ? nil : Int(digits)
            draft.valueTouched = true
            // With a hand-picked emoji too, nothing an answer brings could still be used.
            if draft.emoji != nil {
                suggestionTask?.cancel()
                suggestionTask = nil
                aiLoading = false
            }
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
    /// pause in typing, asks the selected model for a better emoji and an approximate price.
    func setName(_ name: String) {
        guard name != draft.name else { return }
        // An estimate belongs to the name it was made for; it must not be saved under another one.
        if name.trimmingCharacters(in: .whitespacesAndNewlines)
            != draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        {
            draft.estimatedValue = nil
        }
        draft.name = name
        hasEditedName = true
        // Without a specific keyword match, keep the emoji the gift already had instead of the generic one.
        draft.aiEmoji = suggestGift.keywordSuggestion(for: name) == nil ? storedEmoji : nil
        scheduleSuggestion(after: debounce)
    }

    private func scheduleSuggestion(after delay: Duration) {
        suggestionTask?.cancel()
        suggestionTask = nil
        aiLoading = false
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A hand-picked emoji still leaves the price to estimate while the user hasn't entered one.
        let wantsAnswer = draft.emoji == nil || !draft.valueTouched
        guard wantsAnswer, trimmed.count >= 2, suggestGift.isIntelligenceAvailable else {
            // No answer is coming for this name, so an estimate for an earlier one would be stale.
            draft.estimatedValue = nil
            return
        }
        suggestionTask = Task {
            try? await Task.sleep(for: delay)
            guard !isStale(trimmed) else { return }
            // The spinner belongs to the icon, so it stays hidden over a hand-picked emoji.
            aiLoading = draft.emoji == nil
            let provider: SuggestionProvider = preferences?.cloudIconConsent == .allowed ? .cloud : .onDevice
            let started = Date()
            let result = await suggestGift.intelligentSuggestion(for: trimmed, currency: currency)
            // A request the user typed past was cancelled; only answers that arrive are measured.
            guard !isStale(trimmed) else { return }
            analytics.track(
                .giftSuggestionCompleted(
                    provider: provider,
                    hasIcon: result?.emoji != nil,
                    hasPrice: result?.value != nil,
                    latencyMilliseconds: Int(Date().timeIntervalSince(started) * 1_000)))
            aiLoading = false
            if let emoji = result?.emoji, draft.emoji == nil { draft.aiEmoji = emoji }
            // The user's own value always wins; an answer without a price clears an earlier estimate.
            if !draft.valueTouched { draft.estimatedValue = result?.value }
        }
    }

    /// The currency the estimate is asked for: the app's current one, or USD without preferences.
    private var currency: SupportedCurrency {
        preferences.flatMap { SupportedCurrency(rawValue: $0.currencyCode) } ?? .usd
    }

    /// True once this inference was cancelled or the name moved on. Whoever cancelled it
    /// already reset `aiLoading` or started the newer inference that now owns it.
    private func isStale(_ trimmedName: String) -> Bool {
        Task.isCancelled
            || draft.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
    }

    func open(_ picker: AddGiftPicker) {
        self.picker = picker
        analytics.track(.giftPickerOpened(picker.analyticsKind))
    }
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
        pickEmoji(emoji, custom: false)
    }

    private func pickEmoji(_ emoji: String, custom: Bool) {
        draft.emoji = emoji
        analytics.track(.giftIconPicked(custom: custom))
        // An answer still on its way can bring the price; it never replaces the picked emoji.
        if draft.valueTouched {
            suggestionTask?.cancel()
            suggestionTask = nil
        }
        aiLoading = false
        picker = nil
    }
    func selectDate(_ date: Date) { draft.date = date; picker = nil }

    func useCustomEmoji(_ value: String) {
        let emoji = value.firstGrapheme
        guard !emoji.isEmpty else { return }
        pickEmoji(emoji, custom: true)
    }

    func save(using composition: AppComposition) {
        guard input.canSave else { return }
        let saved = composition.saveGift(input)
        // A programmatic switch, not a tab tap, so it sets the tab directly.
        if saved, editingGiftID == nil { composition.router.tab = .home }
        composition.router.dismissGiftSheet(outcome: saved ? .saved : .failed)
    }

    func cancel() {
        suggestionTask?.cancel()
        suggestionTask = nil
        aiLoading = false
    }
}

extension AddGiftPicker {
    var analyticsKind: GiftPickerKind {
        switch self {
        case .from: .giver
        case .to: .recipient
        case .occasion: .occasion
        case .emoji: .icon
        case .date: .date
        }
    }
}
