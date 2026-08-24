import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Best-effort on-device enrichment of a gift name → representative emoji + a
/// rough ruble estimate. Uses Apple's on-device language model (iOS 26+, Apple
/// Intelligence) when available; works in any language, including Russian.
///
/// Callers keep the synchronous keyword heuristic (`SuggestGiftUseCase`) for
/// instant feedback and only *layer* this on top — so when the model is absent
/// (older devices, simulator, Apple Intelligence off) nothing regresses.
@MainActor
final class FoundationModelsGiftIntelligenceGateway: GiftIntelligenceGateway {

    /// Whether the on-device model is usable right now. False on the simulator,
    /// on devices without Apple Intelligence, when the user hasn't enabled it, or
    /// while the model is still downloading — callers skip the spinner then.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Returns nil when the on-device model can't be used, so callers fall back
    /// to the keyword heuristic.
    func suggestGift(named name: String) async -> GiftIntelligenceResult? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try? await parseWithModel(trimmed)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func parseWithModel(_ text: String) async throws -> GiftIntelligenceResult? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(instructions: """
        You help a Russian-language gift-tracking app. Gift names arrive most \
        often in Russian (e.g. "духи", "букет роз", "шоколадка", "конструктор \
        Лего"), sometimes in English. First understand what the gift actually \
        is, in whatever language it's written. Then do two things:
        1. Pick exactly ONE emoji (a single emoji character) that best \
        represents that gift. Choose a specific, recognisable emoji — e.g. 💐 \
        for flowers, 🌸 for perfume, 🍫 for chocolate, 📱 for a phone, 💍 for \
        jewellery, 🧸 for a toy, 📚 for a book.
        2. Estimate a realistic retail price for a typical version of that gift \
        in Russian rubles (RUB) at present-day prices, as a single positive \
        number with no currency symbol or thousands separators.
        Return only the structured result.
        """)

        let response = try await session.respond(to: "Подарок: \"\(text)\"", generating: AIGift.self)
        let g = response.content
        // Keep just the first grapheme cluster so multi-scalar emoji (🕯️, 🧑‍🍳)
        // survive intact and any stray words the model appends are dropped.
        let emoji = g.emoji.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? ""
        guard !emoji.isEmpty else { return nil }
        return GiftIntelligenceResult(emoji: emoji, value: max(0, g.rubleValue).rounded())
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AIGift {
    @Guide(description: "Exactly one emoji character that best represents this gift")
    var emoji: String
    @Guide(description: "Estimated typical retail price of this gift in Russian rubles (RUB), a positive number with no symbols")
    var rubleValue: Double
}
#endif
