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

    func suggestGift(named name: String) async -> GiftIntelligenceResult? {
        let consent = preferences.cloudIconConsent
        let gateway = selected
        guard gateway.isAvailable else { return nil }
        let result = await gateway.suggestGift(named: name)
        guard !Task.isCancelled, preferences.cloudIconConsent == consent else { return nil }
        return result
    }
}

/// Deterministic verification launches never contact the cloud provider.
@MainActor
final class StubCloudGiftIconGateway: GiftIntelligenceGateway {
    var isAvailable: Bool { true }
    func prewarm() {}

    func suggestGift(named name: String) async -> GiftIntelligenceResult? {
        let emoji: String? =
            switch CloudGiftIconGateway.normalizedName(name).lowercased() {
            case "гитара", "guitar": "🎸"
            case "кроссовки", "running shoes": "👟"
            default: nil
            }
        return emoji.map { GiftIntelligenceResult(emoji: $0, value: 0) }
    }
}
