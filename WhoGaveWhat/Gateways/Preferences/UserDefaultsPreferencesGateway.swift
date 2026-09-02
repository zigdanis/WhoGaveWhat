import Foundation

@MainActor
final class UserDefaultsPreferencesGateway: PreferencesGateway {
    private let defaults: UserDefaults
    private let onboardingKey = "didOnboard"
    private let currencyCodeKey = "preferredCurrencyCode"

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

    func setDidCompleteOnboarding(_ completed: Bool) {
        defaults.set(completed, forKey: onboardingKey)
    }

    func setCurrencyCode(_ currencyCode: String) {
        defaults.set(currencyCode, forKey: currencyCodeKey)
    }
}
