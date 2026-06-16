import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Best-effort on-device enrichment of a gift name → representative emoji + a
/// rough ruble estimate. Uses Apple's on-device language model (iOS 26+, Apple
/// Intelligence) when available; works in any language, including Russian.
///
/// Callers keep the synchronous keyword heuristic (`AppStore.suggest`) for
/// instant feedback and only *layer* this on top — so when the model is absent
/// (older devices, simulator, Apple Intelligence off) nothing regresses.
enum GiftParser {
    struct Result { let emoji: String; let value: Double }

    /// Returns nil when the on-device model can't be used, so callers fall back
    /// to the keyword heuristic.
    static func parse(_ name: String) async -> Result? {
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
    private static func parseWithModel(_ text: String) async throws -> Result? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(instructions: """
        You help a gift-tracking app. Given the name of a gift — in any \
        language, very often Russian — do two things:
        1. Pick exactly ONE emoji that best represents the gift.
        2. Estimate a realistic price for a typical version of that gift, in \
        Russian rubles (RUB), as a positive number.
        Return only the structured result.
        """)

        let response = try await session.respond(to: "Gift: \"\(text)\"", generating: AIGift.self)
        let g = response.content
        let emoji = String(g.emoji.prefix(2)).trimmingCharacters(in: .whitespaces)
        guard !emoji.isEmpty else { return nil }
        return Result(emoji: emoji, value: max(0, g.rubleValue).rounded())
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AIGift {
    @Guide(description: "A single emoji that best represents this gift")
    var emoji: String
    @Guide(description: "Estimated typical price of this gift in Russian rubles (RUB), a positive number")
    var rubleValue: Double
}
#endif
