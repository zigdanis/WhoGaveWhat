import Foundation

/// The currencies the app offers. Gift values are plain numbers shown in the chosen one;
/// there is no per-gift currency and no conversion.
enum SupportedCurrency: String, CaseIterable, Sendable {
    case rub = "RUB"
    case usd = "USD"

    var code: String { rawValue }

    /// A stored RUB or USD wins and any other stored code becomes USD. Without a stored code the
    /// locale's currency decides: RUB for Russian rubles, USD for everything else.
    static func resolve(stored: String?, localeCurrency: String?) -> SupportedCurrency {
        if let stored, !stored.isEmpty {
            return SupportedCurrency(rawValue: stored) ?? .usd
        }
        return localeCurrency == SupportedCurrency.rub.code ? .rub : .usd
    }
}
