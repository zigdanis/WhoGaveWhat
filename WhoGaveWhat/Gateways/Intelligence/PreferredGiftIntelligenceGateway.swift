@MainActor
final class PreferredGiftIntelligenceGateway: GiftIntelligenceGateway {
    private let preferences: PreferencesGateway
    private let cloud: GiftIntelligenceGateway
    private let onDevice: GiftIntelligenceGateway

    init(preferences: PreferencesGateway, cloud: GiftIntelligenceGateway, onDevice: GiftIntelligenceGateway) {
        self.preferences = preferences
        self.cloud = cloud
        self.onDevice = onDevice
    }

    private var selected: GiftIntelligenceGateway {
        preferences.cloudIconConsent == .allowed ? cloud : onDevice
    }

    var isAvailable: Bool { selected.isAvailable }
    func prewarm() { selected.prewarm() }

    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult? {
        let consent = preferences.cloudIconConsent
        let gateway = selected
        guard gateway.isAvailable else { return nil }
        let result = await gateway.suggestGift(named: name, currency: currency)
        guard !Task.isCancelled, preferences.cloudIconConsent == consent else { return nil }
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
