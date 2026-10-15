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
    /// Holds a session that is already loaded but has not served a request yet.
    /// Each request consumes it, so every prompt starts from a clean transcript
    /// (a long-lived session would grow its context with every keystroke-driven call).
    private var warmSession: Any?

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

    func prewarm() {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard isAvailable, warmSession == nil else { return }
                let session = Self.makeSession()
                session.prewarm()
                warmSession = session
            }
        #endif
    }

    /// Returns nil when the on-device model can't be used or its answer is not a
    /// single emoji, so callers fall back to the keyword heuristic.
    func suggestGift(named name: String) async -> GiftIntelligenceResult? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard isAvailable else { return nil }
                let session = (warmSession as? LanguageModelSession) ?? Self.makeSession()
                warmSession = nil
                defer { prewarm() }
                return try? await respond(to: trimmed, using: session)
            }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        private static func makeSession() -> LanguageModelSession {
            LanguageModelSession(instructions: instructions)
        }

        @available(iOS 26.0, *)
        private func respond(to text: String, using session: LanguageModelSession) async throws
            -> GiftIntelligenceResult?
        {
            let response = try await session.respond(
                to: "Gift: \(text)",
                generating: AIGift.self,
                options: GenerationOptions(temperature: 0.2)
            )
            let gift = response.content
            guard let emoji = GiftEmoji.validated(gift.emoji) else { return nil }
            return GiftIntelligenceResult(emoji: emoji, value: max(0, gift.rubleValue).rounded())
        }

        private static let instructions = """
            You pick the icon for a gift in a personal gift-tracking app. The gift name is \
            a short phrase, usually in Russian and sometimes in English, with typos or \
            brand names. Understand what the physical thing or experience is, then answer:
            - emoji: exactly ONE emoji character, no words and no spaces. Choose the most \
            specific and recognisable emoji for the item itself, not a generic gift box. \
            Use 🎁 only when nothing fits.
            - rubleValue: a realistic present-day retail price in Russian rubles for a \
            typical version of the item, as one positive number.

            Examples:
            Gift: букет роз -> emoji 💐, rubleValue 3000
            Gift: духи Chanel -> emoji 🌸, rubleValue 9000
            Gift: шоколадка Алёнка -> emoji 🍫, rubleValue 120
            Gift: конструктор Лего -> emoji 🧱, rubleValue 4000
            Gift: AirPods Pro -> emoji 🎧, rubleValue 25000
            Gift: билеты в театр -> emoji 🎭, rubleValue 6000
            Gift: красное вино -> emoji 🍷, rubleValue 1500
            Gift: running shoes -> emoji 👟, rubleValue 8000
            Gift: плюшевый мишка -> emoji 🧸, rubleValue 1500
            """
    #endif
}

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct AIGift {
        @Guide(description: "Exactly one emoji character for the gift, with no text or whitespace")
        var emoji: String
        @Guide(description: "Typical retail price of this gift in Russian rubles (RUB), a positive number with no symbols")
        var rubleValue: Double
    }
#endif
