import Foundation
import SwiftUI

enum DesignMetrics {
    static let cornerRadius: CGFloat = 8
}

extension Font {
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Subtle ink card shadow. Grouped cards sit flat on the field; this is reserved
/// for lifted surfaces (onboarding tiles, the floating "Add a gift" pill).
extension View {
    func ksCardShadow(strong: Bool = false) -> some View {
        shadow(
            color: Color(hex: 0x10141C, alpha: strong ? 0.14 : 0.06),
            radius: strong ? 10 : 2,
            x: 0,
            y: strong ? 6 : 1
        )
    }
}

func formattedCurrency(
    _ value: Double,
    code: String,
    locale: Locale = .autoupdatingCurrent
) -> String {
    value.formatted(
        .currency(code: code)
            .precision(.fractionLength(0))
            .locale(locale)
    )
}

func currencySymbol(code: String, locale: Locale = .autoupdatingCurrent) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    return formatter.currencySymbol ?? code
}
