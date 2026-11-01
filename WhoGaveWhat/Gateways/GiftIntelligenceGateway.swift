struct GiftIntelligenceResult: Equatable {
    let emoji: String?
    /// Approximate price in the requested currency; nil when there is no estimate.
    let value: Int?
    /// Which service answered; set by the gateway that routes between them, nil for a single service.
    var provider: SuggestionProvider?
}

@MainActor
protocol GiftIntelligenceGateway: AnyObject {
    var isAvailable: Bool { get }
    /// Loads the model ahead of the first request. Safe to call repeatedly.
    func prewarm()
    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult?
}
