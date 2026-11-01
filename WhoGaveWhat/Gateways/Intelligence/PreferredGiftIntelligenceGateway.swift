/// Asks the cloud service first; when it has no answer (offline, rate limited, low confidence) and the
/// on-device model is available, that model gets the same question. Results are stamped with who answered.
@MainActor
final class PreferredGiftIntelligenceGateway: GiftIntelligenceGateway {
    private let cloud: GiftIntelligenceGateway
    private let onDevice: GiftIntelligenceGateway

    init(cloud: GiftIntelligenceGateway, onDevice: GiftIntelligenceGateway) {
        self.cloud = cloud
        self.onDevice = onDevice
    }

    var isAvailable: Bool { cloud.isAvailable || onDevice.isAvailable }

    /// Only the cloud route is warmed: it is the one every request tries first.
    func prewarm() { cloud.prewarm() }

    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult? {
        if cloud.isAvailable, var result = await cloud.suggestGift(named: name, currency: currency) {
            result.provider = .cloud
            return result
        }
        guard !Task.isCancelled, onDevice.isAvailable,
            var result = await onDevice.suggestGift(named: name, currency: currency)
        else { return nil }
        result.provider = .onDevice
        return result
    }
}

/// Deterministic verification launches never contact the cloud provider.
@MainActor
final class StubCloudGiftIconGateway: GiftIntelligenceGateway {
    var isAvailable: Bool { true }
    func prewarm() {}

    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult? {
        let guess: (emoji: String, rub: Int, usd: Int)? =
            switch CloudGiftIconGateway.normalizedName(name).lowercased() {
            case "гитара", "guitar": ("🎸", 10_000, 150)
            case "кроссовки", "running shoes": ("👟", 5_000, 100)
            default: nil
            }
        return guess.map {
            GiftIntelligenceResult(emoji: $0.emoji, value: currency == .rub ? $0.rub : $0.usd)
        }
    }
}
