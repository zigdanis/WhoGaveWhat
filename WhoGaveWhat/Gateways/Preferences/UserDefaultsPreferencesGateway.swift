import Foundation
import Observation

@MainActor
@Observable
final class UserDefaultsPreferencesGateway: PreferencesGateway {
    private let defaults: UserDefaults
    private let currencyCodeKey = "preferredCurrencyCode"
    private let selfPersonKey = "selfPersonID"
    private let installIDKey = "cloudIconInstallID"
    private let recentInsightsPicksKeyPrefix = "insightsRecentPicks."
    private let reviewPromptKey = "reviewPrompt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var installID: String {
        if let storedID = defaults.string(forKey: installIDKey), UUID(uuidString: storedID) != nil {
            return storedID
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: installIDKey)
        return id
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

    var reviewPromptState: ReviewPromptState {
        guard let data = defaults.data(forKey: reviewPromptKey),
            let state = try? JSONDecoder().decode(ReviewPromptState.self, from: data)
        else { return ReviewPromptState() }
        return state
    }

    func setReviewPromptState(_ state: ReviewPromptState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: reviewPromptKey)
    }
}
