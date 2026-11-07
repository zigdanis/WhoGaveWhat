import Foundation

/// The currencies the app offers. Every gift keeps its value in its own currency; the preference
/// is only the default for new gifts. Amounts in different currencies are never converted or added.
enum SupportedCurrency: String, CaseIterable, Identifiable, Sendable {
    case rub = "RUB"
    case usd = "USD"

    var code: String { rawValue }
    var id: String { rawValue }

    /// A stored RUB or USD wins and any other stored code becomes USD. Without a stored code the
    /// locale's currency decides: RUB for Russian rubles, USD for everything else.
    static func resolve(stored: String?, localeCurrency: String?) -> SupportedCurrency {
        if let stored, !stored.isEmpty {
            return SupportedCurrency(rawValue: stored) ?? .usd
        }
        return localeCurrency == SupportedCurrency.rub.code ? .rub : .usd
    }
}
