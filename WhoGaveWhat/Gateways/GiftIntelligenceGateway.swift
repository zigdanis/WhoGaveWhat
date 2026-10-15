struct GiftIntelligenceResult: Equatable {
    let emoji: String
    let value: Double
}

@MainActor
protocol GiftIntelligenceGateway: AnyObject {
    var isAvailable: Bool { get }
    /// Loads the model ahead of the first request. Safe to call repeatedly.
    func prewarm()
    func suggestGift(named name: String) async -> GiftIntelligenceResult?
}
