import SwiftUI

/// Who Gave design tokens — ported from the Claude Design "Gift Tracker" prototype.
/// Cool ink + emerald palette on white paper, hairline-bordered cards, 8px corners,
/// heavy Archivo type (bundled). `KS` = the app's style namespace.
enum KS {
    // Semantic palette
    static let recv      = Color(hex: 0x12805C)   // emerald — Received
    static let recvDeep  = Color(hex: 0x0E6B4D)
    static let recvTint  = Color(hex: 0xE6F2EC)
    static let give      = Color(hex: 0x12161C)   // ink — Given
    static let giveDeep  = Color(hex: 0x000000)
    static let giveTint  = Color(hex: 0xEEF0F3)
    static let gold      = Color(hex: 0x5B6573)   // slate — neutral bars

    // Surfaces & ink
    static let bg        = Color(hex: 0xFFFFFF)
    static let card      = Color.white
    static let ink       = Color(hex: 0x12161C)

    // Muted text shades
    static let muted     = Color(hex: 0x8A95A3)
    static let muted2    = Color(hex: 0x6C7686)
    static let muted3    = Color(hex: 0x7C8694)
    static let muted4    = Color(hex: 0x9AA3B0)
    static let chevron   = Color(hex: 0xC2CAD4)
    static let hairline  = Color(hex: 0xEEF1F5)   // row dividers
    static let track     = Color(hex: 0xEEF1F5)   // bar backgrounds
    static let border    = Color(hex: 0xE1E6EC)   // field / chip borders
    static let cardBorder = Color(hex: 0xE6EAEF)  // hairline card outline
    static let chipText  = Color(hex: 0x3A424E)   // unselected chip label

    // App background gradient (behind the device content)
    static let pageTop   = Color(hex: 0xEEF1F4)

    /// Corner radius used across the design (cards, chips, buttons, tiles).
    static let radius: CGFloat = 8

    /// Bundled Archivo, mapped from SwiftUI weights to static faces.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(faceName(weight), size: size)
    }

    private static func faceName(_ w: Font.Weight) -> String {
        switch w {
        case .black:    return "Archivo-Black"
        case .heavy:    return "Archivo-ExtraBold"
        case .bold:     return "Archivo-Bold"
        case .semibold: return "Archivo-SemiBold"
        case .medium:   return "Archivo-Medium"
        default:        return "Archivo-Regular"
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Subtle ink card shadow (design uses `0 1px 2px rgba(16,20,28,.06)`).
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

/// Ruble formatting with thin-space grouping, matching the prototype `fmt()`.
func rub(_ value: Double) -> String {
    let n = Int(value.rounded())
    var digits = String(abs(n))
    var groups: [String] = []
    while digits.count > 3 {
        let idx = digits.index(digits.endIndex, offsetBy: -3)
        groups.insert(String(digits[idx...]), at: 0)
        digits = String(digits[..<idx])
    }
    groups.insert(digits, at: 0)
    let grouped = groups.joined(separator: "\u{202F}")
    return (n < 0 ? "-" : "") + grouped + "\u{00A0}₽"
}
