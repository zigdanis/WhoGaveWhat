import Foundation

/// The round price steps a gift estimate snaps to, per currency. The icon Worker's `prices.ts`
/// holds the same lists for the cloud estimate; keep them identical.
enum GiftPriceBuckets {
    static func buckets(for currency: SupportedCurrency) -> [Int] {
        switch currency {
        case .rub: [300, 500, 1_000, 2_000, 3_000, 5_000, 10_000, 15_000, 20_000, 30_000, 50_000, 100_000, 200_000, 500_000, 1_000_000]
        case .usd: [5, 10, 20, 30, 50, 100, 150, 200, 300, 500, 1_000, 2_000, 5_000, 10_000, 20_000]
        }
    }

    /// The bucket nearest to `value` in log space, so 4 000 lands on 3 000 and 4 500 on 5 000.
    /// Values beyond either end take the end bucket; zero, negative and non-finite values have none.
    static func snap(_ value: Double, currency: SupportedCurrency) -> Int? {
        guard value.isFinite, value > 0 else { return nil }
        let target = log(value)
        return buckets(for: currency).min { abs(log(Double($0)) - target) < abs(log(Double($1)) - target) }
    }
}
