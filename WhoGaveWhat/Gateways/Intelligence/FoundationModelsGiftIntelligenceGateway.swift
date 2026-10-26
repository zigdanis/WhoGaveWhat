import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Best-effort on-device enrichment of a gift name → representative emoji + a
/// rough price estimate in the app's currency. Uses Apple's on-device language model (iOS 26+, Apple
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
    private let analytics: AnalyticsGateway

    init(analytics: AnalyticsGateway = NoopAnalyticsGateway()) {
        self.analytics = analytics
    }

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

    /// Returns nil when the on-device model can't be used or gives neither a single emoji
    /// nor a price, so callers fall back to the keyword heuristic.
    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard isAvailable else { return nil }
                let session = (warmSession as? LanguageModelSession) ?? Self.makeSession()
                warmSession = nil
                defer { prewarm() }
                do {
                    return try await respond(to: trimmed, currency: currency, using: session)
                } catch is CancellationError {
                    return nil
                } catch {
                    analytics.report(AnalyticsFailure(operation: "on_device_inference", error: error))
                    return nil
                }
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
        private func respond(to text: String, currency: SupportedCurrency, using session: LanguageModelSession)
            async throws -> GiftIntelligenceResult?
        {
            let response = try await session.respond(
                to: "Gift: \(text)\nCurrency: \(currency.code)",
                generating: AIGift.self,
                options: GenerationOptions(temperature: 0.2)
            )
            let gift = response.content
            // A price is still useful when the emoji is not valid, and the other way round.
            let emoji = GiftEmoji.validated(gift.emoji)
            let value = GiftPriceBuckets.snap(gift.price, currency: currency)
            guard emoji != nil || value != nil else { return nil }
            return GiftIntelligenceResult(emoji: emoji, value: value)
        }

        private static let instructions = """
            You pick the icon for a gift in a personal gift-tracking app. The gift name is \
            a short phrase, usually in Russian and sometimes in English, with typos or \
            brand names. Understand what the physical thing or experience is, then answer:
            - emoji: exactly ONE emoji character, no words and no spaces. Choose the most \
            specific and recognisable emoji for the item itself, not a generic gift box. \
            Use 🎁 only when nothing fits.
            - price: a realistic present-day retail price for a typical version of the \
            item, as one positive number in the currency named in the prompt (RUB or USD).

            Examples:
            Gift: букет роз, Currency: RUB -> emoji 💐, price 3000
            Gift: духи Chanel, Currency: RUB -> emoji 🌸, price 9000
            Gift: шоколадка Алёнка, Currency: RUB -> emoji 🍫, price 120
            Gift: AirPods Pro, Currency: RUB -> emoji 🎧, price 25000
            Gift: билеты в театр, Currency: RUB -> emoji 🎭, price 6000
            Gift: плюшевый мишка, Currency: RUB -> emoji 🧸, price 1500
            Gift: bouquet of roses, Currency: USD -> emoji 💐, price 50
            Gift: Chanel perfume, Currency: USD -> emoji 🌸, price 120
            Gift: chocolate bar, Currency: USD -> emoji 🍫, price 3
            Gift: AirPods Pro, Currency: USD -> emoji 🎧, price 250
            Gift: running shoes, Currency: USD -> emoji 👟, price 100
            Gift: теплый плед, Currency: USD -> emoji 🛏️, price 40
            """
    #endif
}

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct AIGift {
        @Guide(description: "Exactly one emoji character for the gift, with no text or whitespace")
        var emoji: String
        @Guide(description: "Typical retail price of this gift in the currency named in the prompt, a positive number with no symbols")
        var price: Double
    }
#endif
