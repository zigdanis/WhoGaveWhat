struct GiftIntelligenceResult: Equatable {
    let emoji: String
    let value: Double
}

@MainActor
protocol GiftIntelligenceGateway: AnyObject {
    var isAvailable: Bool { get }
    func suggestGift(named name: String) async -> GiftIntelligenceResult?
}
