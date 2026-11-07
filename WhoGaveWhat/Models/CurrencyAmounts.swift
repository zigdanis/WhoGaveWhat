import Foundation

/// Money kept apart by currency. Amounts in different currencies are never added together and
/// never converted, so a journal with gifts in rubles and dollars has one total per currency.
struct CurrencyAmounts: Equatable {
    /// The amount in each currency that has an entry, which may be zero.
    private(set) var values: [SupportedCurrency: Double] = [:]

    init() {}

    init(_ values: [SupportedCurrency: Double]) {
        self.values = values
    }

    subscript(currency: SupportedCurrency) -> Double {
        values[currency] ?? 0
    }

    mutating func add(_ amount: Double, in currency: SupportedCurrency) {
        values[currency, default: 0] += amount
    }

    /// Currencies with an entry, in `SupportedCurrency.allCases` order.
    var currencies: [SupportedCurrency] {
        SupportedCurrency.allCases.filter { values[$0] != nil }
    }

    /// Currencies whose amount does not round to zero, in `SupportedCurrency.allCases` order.
    var nonZeroCurrencies: [SupportedCurrency] {
        currencies.filter { self[$0].rounded() != 0 }
    }

    /// True when every amount rounds to zero, including when there is none.
    var isEven: Bool { nonZeroCurrencies.isEmpty }

    /// The sign shared by every amount that does not round to zero.
    var sign: CurrencyAmountsSign {
        let signs = Set(nonZeroCurrencies.map { self[$0] > 0 })
        switch (signs.contains(true), signs.contains(false)) {
        case (false, false): return .even
        case (true, false): return .positive
        case (false, true): return .negative
        case (true, true): return .mixed
        }
    }

    /// The amounts to show, `preferred` first and then in `SupportedCurrency.allCases` order: every
    /// currency whose amount does not round to zero. When none does, one zero in the only currency
    /// with an entry, or in `preferred` when there are several or none.
    func displayed(preferred: SupportedCurrency) -> [CurrencyAmount] {
        let shown = nonZeroCurrencies
        guard !shown.isEmpty else {
            let present = currencies
            return [CurrencyAmount(currency: present.count == 1 ? present[0] : preferred, amount: 0)]
        }
        let ordered = shown.filter { $0 == preferred } + shown.filter { $0 != preferred }
        return ordered.map { CurrencyAmount(currency: $0, amount: self[$0]) }
    }

    /// The per-currency difference; a currency with an entry on either side has one in the result.
    static func - (lhs: CurrencyAmounts, rhs: CurrencyAmounts) -> CurrencyAmounts {
        var result = lhs
        for (currency, amount) in rhs.values {
            result.add(-amount, in: currency)
        }
        return result
    }

    /// Orders by size without converting: the absolute rounded amounts are compared currency by
    /// currency in `SupportedCurrency.allCases` order. Nil when they are equal.
    static func largerMagnitude(_ lhs: CurrencyAmounts, _ rhs: CurrencyAmounts) -> Bool? {
        for currency in SupportedCurrency.allCases {
            let left = abs(lhs[currency].rounded())
            let right = abs(rhs[currency].rounded())
            if left != right { return left > right }
        }
        return nil
    }
}

/// One amount in one currency.
struct CurrencyAmount: Identifiable, Equatable {
    let currency: SupportedCurrency
    let amount: Double

    var id: SupportedCurrency { currency }
}

enum CurrencyAmountsSign: Equatable {
    case even
    case positive
    case negative
    /// Ahead in one currency and behind in another; with no exchange rate there is no overall sign.
    case mixed
}

extension Collection where Element == Gift {
    /// The sum of the values, one per currency.
    var totals: CurrencyAmounts {
        reduce(into: CurrencyAmounts()) { result, gift in
            result.add(gift.value, in: gift.currency)
        }
    }
}
