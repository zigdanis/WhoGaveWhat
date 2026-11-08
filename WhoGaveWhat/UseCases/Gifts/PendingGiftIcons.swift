import Foundation
import Observation

/// An icon inference that can outlive the gift sheet: the gift name it was asked for, its currency
/// and, once it was sent, the request itself.
struct GiftIconRequest {
    /// The trimmed gift name the icon is for.
    let name: String
    let currency: SupportedCurrency
    let startedAt: Date
    /// The request already on its way, or nil when the gift was saved before it was sent.
    let task: Task<GiftIntelligenceResult?, Never>?
}

/// Icon inferences for gifts saved before the model answered. They are owned by the app rather than
/// the gift sheet, so a quick Save no longer cuts them off: each one keeps running after the sheet closes
/// and its answer is handed back once it arrives. A newer request for the same gift replaces the older one.
@MainActor
@Observable
final class PendingGiftIcons {
    /// Gifts whose icon is still being inferred.
    private(set) var giftIDs: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// The trimmed name each pending icon is for.
    @ObservationIgnored private var names: [String: String] = [:]
    @ObservationIgnored private let suggestGift: SuggestGiftUseCase

    init(suggestGift: SuggestGiftUseCase) {
        self.suggestGift = suggestGift
    }

    func contains(_ giftID: String) -> Bool {
        giftIDs.contains(giftID)
    }

    /// The wait for a gift's answer while it runs; tests await it.
    func task(for giftID: String) -> Task<Void, Never>? {
        tasks[giftID]
    }

    /// Follows the request for the saved gift: reuses the one already sent, or sends it now, and calls
    /// `onAnswer` with whatever comes back. A replaced request is cancelled and never answers.
    func follow(
        _ request: GiftIconRequest,
        giftID: String,
        onAnswer: @escaping @MainActor (GiftIntelligenceResult?) -> Void
    ) {
        tasks[giftID]?.cancel()
        giftIDs.insert(giftID)
        names[giftID] = request.name
        let suggestGift = suggestGift
        let inference =
            request.task
            ?? Task { await suggestGift.intelligentSuggestion(for: request.name, currency: request.currency) }
        tasks[giftID] = Task {
            let result = await withTaskCancellationHandler {
                await inference.value
            } onCancel: {
                inference.cancel()
            }
            // A replaced request leaves the gift to the newer one.
            guard !Task.isCancelled else { return }
            tasks[giftID] = nil
            names[giftID] = nil
            giftIDs.remove(giftID)
            onAnswer(result)
        }
    }

    /// Stops waiting when the saved gift no longer wants the answer: it was renamed or has a hand-picked
    /// icon. Its row then drops the spinner at once instead of when the request ends.
    func stopIfOutdated(giftID: String, current gift: Gift) {
        guard let name = names[giftID] else { return }
        guard gift.emojiPickedByUser || gift.name.trimmingCharacters(in: .whitespacesAndNewlines) != name else {
            return
        }
        stop(giftID: giftID)
    }

    /// Stops waiting for a gift's icon; its answer, if any comes, is dropped.
    func stop(giftID: String) {
        tasks[giftID]?.cancel()
        tasks[giftID] = nil
        names[giftID] = nil
        giftIDs.remove(giftID)
    }
}
