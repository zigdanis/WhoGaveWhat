import Foundation

@MainActor
final class UserDefaultsPreferencesGateway: PreferencesGateway {
    private let defaults: UserDefaults
    private let onboardingKey = "didOnboard"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var didCompleteOnboarding: Bool {
        defaults.bool(forKey: onboardingKey)
    }

    func setDidCompleteOnboarding(_ completed: Bool) {
        defaults.set(completed, forKey: onboardingKey)
    }
}
