import Foundation
import Observation

@MainActor
@Observable
final class UserDefaultsPreferencesGateway: PreferencesGateway {
    private let defaults: UserDefaults
    private let onboardingKey = "didOnboard"
    private let currencyCodeKey = "preferredCurrencyCode"
    private let selfPersonKey = "selfPersonID"
    /// Static so the initializer can read it before every stored property is set.
    private static let cloudIconConsentKey = "cloudIconConsent"
    private let installIDKey = "cloudIconInstallID"
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

    var didCompleteOnboarding: Bool {
        defaults.bool(forKey: onboardingKey)
    }

    var currencyCode: String {
        if let storedCode = defaults.string(forKey: currencyCodeKey), !storedCode.isEmpty {
            return storedCode
        }
        let inferredCode = Locale.current.currency?.identifier ?? "USD"
        defaults.set(inferredCode, forKey: currencyCodeKey)
        return inferredCode
    }

    var selfPersonID: String? {
        guard let storedID = defaults.string(forKey: selfPersonKey), !storedID.isEmpty else { return nil }
        return storedID
    }

    func setDidCompleteOnboarding(_ completed: Bool) {
        defaults.set(completed, forKey: onboardingKey)
    }

    func setCurrencyCode(_ currencyCode: String) {
        defaults.set(currencyCode, forKey: currencyCodeKey)
    }

    func setSelfPersonID(_ id: String?) {
        if let id {
            defaults.set(id, forKey: selfPersonKey)
        } else {
            defaults.removeObject(forKey: selfPersonKey)
        }
    }
}
