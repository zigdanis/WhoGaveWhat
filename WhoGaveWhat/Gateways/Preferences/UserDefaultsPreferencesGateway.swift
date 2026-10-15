import Foundation

@MainActor
final class UserDefaultsPreferencesGateway: PreferencesGateway {
    private let defaults: UserDefaults
    private let onboardingKey = "didOnboard"
    private let currencyCodeKey = "preferredCurrencyCode"
    private let selfPersonKey = "selfPersonID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
