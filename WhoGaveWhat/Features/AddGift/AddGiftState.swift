import Foundation
import Observation

@MainActor
@Observable
final class AddGiftState {
    var draft = AddGiftDraft()
    var picker: AddGiftPicker?
    var aiLoading = false
    /// True after a save the store refused, while the error is shown. The sheet and the draft stay as they were.
    var isShowingSaveError = false

    private(set) var editingGiftID: String?
    private let suggestGift: SuggestGiftUseCase
    private let debounce: Duration
    private let analytics: AnalyticsGateway
    private var hasEditedPrice = false
    private(set) var suggestionTask: Task<Void, Never>?
    /// The trimmed name whose inference is scheduled or running and has not answered yet.
    private var pendingSuggestionName: String?
    /// The request that inference sent, once it was sent. Saving can hand it over to the app.
    private var inFlightRequest: GiftIconRequest?
    /// The automatically chosen emoji a gift being edited already has; kept until a rename yields a better guess.
    private var storedEmoji: String?
    /// True while the inferred icon is still the one the edited gift was stored with: nothing in this sheet
    /// replaced it. Saving then keeps whatever icon the stored gift has by then, including a late one.
    private var inheritsStoredEmoji = false

    init(
        route: GiftSheetRoute,
        data: AppData,
        suggestGift: SuggestGiftUseCase,
        preferences: PreferencesGateway? = nil,
        debounce: Duration = .milliseconds(500),
        analytics: AnalyticsGateway = NoopAnalyticsGateway()
    ) {
        self.suggestGift = suggestGift
        self.debounce = debounce
        self.analytics = analytics
        editingGiftID = route.editingGiftID
        // A new gift starts in the default currency; an edited one keeps its own below.
        draft.currency = preferences?.defaultCurrency ?? .usd

        if let giftID = route.editingGiftID,
            let gift = data.gifts.first(where: { $0.id == giftID })
        {
            // An emoji the user picked stays sticky; an inferred one is re-inferred on rename.
            draft = AddGiftDraft(
                name: gift.name,
                emoji: gift.emojiPickedByUser ? gift.emoji : nil,
                value: Int(gift.value),
                valueTouched: true,
                currency: gift.currency,
                fromID: gift.giverID,
                toID: gift.recipientID,
                paidByYou: gift.paidByYou,
                occasion: gift.occasion,
                date: gift.date,
                createdAt: gift.createdAt,
                aiEmoji: gift.emojiPickedByUser ? nil : gift.emoji
            )
            if !gift.emojiPickedByUser {
                storedEmoji = gift.emoji
                inheritsStoredEmoji = true
            }
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
            estimatedCurrency: draft.estimatedCurrency,
            currency: draft.currency,
            fromID: draft.fromID,
            toID: draft.toID,
            paidByYou: draft.paidByYou,
            occasion: draft.occasion,
            date: draft.date,
            createdAt: draft.createdAt,
            keepsStoredEmoji: draft.emoji == nil && inheritsStoredEmoji
        )
    }

    var effectiveEmoji: String {
        draft.emoji ?? draft.aiEmoji ?? suggestGift.instantSuggestion(for: draft.name).emoji
    }

    var name: String {
        get { draft.name }
        set { setName(newValue) }
    }

    /// The currency of this gift's value; setting it goes through `selectCurrency`.
    var currency: SupportedCurrency {
        get { draft.currency }
        set { selectCurrency(newValue) }
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
            // The first edit in this sheet says whether the user overrode an estimate or a stored value.
            if !hasEditedPrice {
                hasEditedPrice = true
                analytics.track(.giftPriceEdited(hadEstimate: showsEstimate))
            }
            draft.value = digits.isEmpty ? nil : Int(digits)
            draft.valueTouched = true
            // With a hand-picked emoji too, nothing an answer brings could still be used.
            if draft.emoji != nil { cancelSuggestion() }
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
            clearEstimate()
        }
        draft.name = name
        // Without a specific keyword match, keep the emoji the gift already had instead of the generic one.
        let keepsStoredEmoji = suggestGift.keywordSuggestion(for: name) == nil && storedEmoji != nil
        draft.aiEmoji = keepsStoredEmoji ? storedEmoji : nil
        inheritsStoredEmoji = keepsStoredEmoji
        scheduleSuggestion(after: debounce)
    }

    private func scheduleSuggestion(after delay: Duration) {
        cancelSuggestion()
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A hand-picked emoji still leaves the price to estimate while the user hasn't entered one.
        let wantsAnswer = draft.emoji == nil || !draft.valueTouched
        guard wantsAnswer, trimmed.count >= 2, suggestGift.isIntelligenceAvailable else {
            // No answer is coming for this name, so an estimate for an earlier one would be stale.
            clearEstimate()
            return
        }
        pendingSuggestionName = trimmed
        suggestionTask = Task {
            try? await Task.sleep(for: delay)
            guard !isStale(trimmed) else { return }
            // The spinner belongs to the icon, so it stays hidden over a hand-picked emoji.
            aiLoading = draft.emoji == nil
            let started = Date()
            // The price comes back in the currency it was asked for, which the gift keeps if saved with it.
            let currency = draft.currency
            // A separate task, so that a Save can hand the request over instead of cutting it off.
            let suggestGift = suggestGift
            let request = Task { await suggestGift.intelligentSuggestion(for: trimmed, currency: currency) }
            inFlightRequest = GiftIconRequest(name: trimmed, currency: currency, startedAt: started, task: request)
            let result = await request.value
            // A request the user typed past was cancelled; only answers that arrive are measured.
            // After a Save handed it over, the app measures and uses the answer instead.
            guard !isStale(trimmed) else { return }
            pendingSuggestionName = nil
            inFlightRequest = nil
            analytics.track(
                .giftSuggestionCompleted(
                    provider: result?.provider ?? .cloud,
                    hasIcon: result?.emoji != nil,
                    hasPrice: result?.value != nil,
                    latencyMilliseconds: Int(Date().timeIntervalSince(started) * 1_000)))
            aiLoading = false
            if let emoji = result?.emoji, draft.emoji == nil {
                draft.aiEmoji = emoji
                inheritsStoredEmoji = false
            }
            // The user's own value always wins; an answer without a price clears an earlier estimate.
            // A price for a currency the user has since switched away from is dropped; the switch asked again.
            if !draft.valueTouched, draft.currency == currency {
                draft.estimatedValue = result?.value
                draft.estimatedCurrency = result?.value == nil ? nil : currency
            }
        }
    }

    /// Stops the inference in progress, including a request already sent.
    private func cancelSuggestion() {
        suggestionTask?.cancel()
        suggestionTask = nil
        inFlightRequest?.task?.cancel()
        inFlightRequest = nil
        pendingSuggestionName = nil
        aiLoading = false
    }

    /// The icon inference to keep following after Save: the icon is still inferred and the model has not
    /// answered for the saved name yet. It reuses the request already sent, if any.
    var pendingIconRequest: GiftIconRequest? {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.emoji == nil, pendingSuggestionName == trimmed else { return nil }
        if let inFlightRequest, inFlightRequest.name == trimmed { return inFlightRequest }
        return GiftIconRequest(name: trimmed, currency: draft.currency, startedAt: Date(), task: nil)
    }

    private func clearEstimate() {
        draft.estimatedValue = nil
        draft.estimatedCurrency = nil
    }

    /// Sets the currency of this gift's value. A number the user entered keeps its digits and now
    /// means the new currency; an estimate was for the old one, so it is dropped and asked for again.
    func selectCurrency(_ currency: SupportedCurrency) {
        guard currency != draft.currency else { return }
        draft.currency = currency
        guard !draft.valueTouched else { return }
        clearEstimate()
        scheduleSuggestion(after: .zero)
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
        if draft.valueTouched { cancelSuggestion() }
        aiLoading = false
        picker = nil
    }
    func selectDate(_ date: Date) { draft.date = date; picker = nil }

    func useCustomEmoji(_ value: String) {
        let emoji = value.firstGrapheme
        guard !emoji.isEmpty else { return }
        pickEmoji(emoji, custom: true)
    }

    /// Closes the sheet only once the gift is stored. After a failure everything entered stays in the draft
    /// and the error is shown, so Save can simply be tapped again.
    func save(using composition: AppComposition) {
        guard input.canSave else { return }
        let iconRequest = pendingIconRequest
        switch composition.saveGift(input, iconRequest: iconRequest) {
        case .saved:
            // The app now owns the request and keeps it running after the sheet closes.
            if iconRequest != nil { inFlightRequest = nil }
            cancel()
            isShowingSaveError = false
            // A programmatic switch, not a tab tap, so it sets the tab directly.
            if editingGiftID == nil { composition.router.tab = .home }
            composition.router.dismissGiftSheet(outcome: .saved)
        case .failed:
            isShowingSaveError = true
        case .invalid:
            break
        }
    }

    func cancel() {
        cancelSuggestion()
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
