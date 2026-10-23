import Foundation
import Observation

@MainActor
@Observable
final class UserDefaultsPreferencesGateway: PreferencesGateway {
    private let defaults: UserDefaults
    private let currencyCodeKey = "preferredCurrencyCode"
    private let selfPersonKey = "selfPersonID"
    /// Static so the initializer can read it before every stored property is set.
    private static let cloudIconConsentKey = "cloudIconConsent"
    private let installIDKey = "cloudIconInstallID"
    private let recentInsightsPicksKeyPrefix = "insightsRecentPicks."
    private(set) var cloudIconConsent: CloudIconConsent

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedConsent = defaults.string(forKey: Self.cloudIconConsentKey).flatMap(CloudIconConsent.init(rawValue:))
        cloudIconConsent = storedConsent ?? .undecided
    }

    var installID: String {
        if let storedID = defaults.string(forKey: installIDKey), UUID(uuidString: storedID) != nil {
            return storedID
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: installIDKey)
        return id
    }

    func setCloudIconConsent(_ consent: CloudIconConsent) {
        guard cloudIconConsent != consent else { return }
        if consent == .declined {
            defaults.set(UUID().uuidString, forKey: installIDKey)
        }
        defaults.set(consent.rawValue, forKey: Self.cloudIconConsentKey)
        cloudIconConsent = consent
    }

    var currencyCode: String {
        let storedCode = defaults.string(forKey: currencyCodeKey)
        let currency = SupportedCurrency.resolve(
            stored: storedCode, localeCurrency: Locale.current.currency?.identifier)
        // Persists the locale default and rewrites an unsupported stored code, so the choice stays stable.
        if storedCode != currency.code { defaults.set(currency.code, forKey: currencyCodeKey) }
        return currency.code
    }

    var selfPersonID: String? {
        guard let storedID = defaults.string(forKey: selfPersonKey), !storedID.isEmpty else { return nil }
        return storedID
    }

    func setCurrencyCode(_ currencyCode: String) {
        guard let currency = SupportedCurrency(rawValue: currencyCode) else { return }
        defaults.set(currency.code, forKey: currencyCodeKey)
    }

    func setSelfPersonID(_ id: String?) {
        if let id {
            defaults.set(id, forKey: selfPersonKey)
        } else {
            defaults.removeObject(forKey: selfPersonKey)
        }
    }

    func recentInsightsPicks(for slot: InsightsPickerSlot) -> [String] {
        defaults.stringArray(forKey: recentInsightsPicksKeyPrefix + slot.rawValue) ?? []
    }

    func setRecentInsightsPicks(_ ids: [String], for slot: InsightsPickerSlot) {
        defaults.set(ids, forKey: recentInsightsPicksKeyPrefix + slot.rawValue)
    }
}
