import Foundation
import SwiftUI

/// Corner-radius scale. Everything uses continuous corners; nested shapes use
/// `concentric(outer:inset:)` so inner and outer curves stay parallel.
enum DesignMetrics {
    /// Icon wells, chips and small tiles.
    static let radiusSmall: CGFloat = 12
    /// Fields, rows and buttons.
    static let radiusMedium: CGFloat = 16
    /// Cards and grouped surfaces.
    static let radiusLarge: CGFloat = 20
    /// Hero surfaces and sheet-level panels.
    static let radiusXLarge: CGFloat = 28

    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, 0)
    }
}

extension Font {
    /// Dynamic Type text styles in the system font (SF Pro). The point size picks
    /// the nearest text style so every call scales with the user's text size;
    /// `rounded` is for large numerals and amounts.
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular, rounded: Bool = false) -> Font {
        .system(textStyle(for: size), design: rounded ? .rounded : .default, weight: weight)
    }

    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 33...: .largeTitle
        case 26..<33: .title
        case 21..<26: .title2
        case 18..<21: .title3
        case 17..<18: .body
        case 16..<17: .callout
        case 14..<16: .subheadline
        case 13..<14: .footnote
        case 12..<13: .caption
        default: .caption2
        }
    }
}

extension View {
    /// Soft, diffuse shadow for lifted surfaces (onboarding tiles, hero marks).
    /// Grouped cards sit flat on the background; floating controls use glass.
    func softShadow(prominent: Bool = false) -> some View {
        shadow(
            color: Color.black.opacity(prominent ? 0.16 : 0.06),
            radius: prominent ? 18 : 6,
            x: 0,
            y: prominent ? 8 : 2
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

private enum CurrencySymbolCache {
    static let values = NSCache<NSString, NSString>()
}

func currencySymbol(code: String, locale: Locale = .autoupdatingCurrent) -> String {
    let cacheKey = "\(locale.identifier)|\(code)" as NSString
    if let cached = CurrencySymbolCache.values.object(forKey: cacheKey) {
        return cached as String
    }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    let symbol = formatter.currencySymbol ?? code
    CurrencySymbolCache.values.setObject(symbol as NSString, forKey: cacheKey)
    return symbol
}
