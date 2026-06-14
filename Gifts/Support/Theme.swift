import SwiftUI

/// Gifts design tokens — ported from the Claude Design prototype.
/// Warm cream paper, terracotta (given) + sage (received), gold accents,
/// friendly rounded type (Nunito → system rounded fallback).
/// `KS` = the app's style namespace (kept short for readability at call sites).
enum KS {
    // Semantic palette
    static let recv      = Color(hex: 0x6E8E66)   // sage — Received
    static let recvDeep  = Color(hex: 0x50704A)
    static let recvTint  = Color(hex: 0xECF1E7)
    static let give      = Color(hex: 0xBE6A4D)   // terracotta — Given
    static let giveDeep  = Color(hex: 0x9E5238)
    static let giveTint  = Color(hex: 0xF7E8E0)
    static let gold      = Color(hex: 0xC79A45)

    // Surfaces & ink
    static let bg        = Color(hex: 0xFAF4ED)
    static let card      = Color.white
    static let ink       = Color(hex: 0x2B2622)

    // Muted text shades
    static let muted     = Color(hex: 0xA89C8E)
    static let muted2    = Color(hex: 0x8A7F76)
    static let muted3    = Color(hex: 0x9A8F84)
    static let muted4    = Color(hex: 0xB8AEA3)
    static let chevron   = Color(hex: 0xD4C9BC)
    static let hairline  = Color(hex: 0xF5EEE6)
    static let track     = Color(hex: 0xF3ECE3)
    static let border    = Color(hex: 0xEFE7DE)

    // App background gradient (behind the device content)
    static let pageTop   = Color(hex: 0xF5EBDF)

    /// Rounded font in the spirit of Nunito.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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

/// Soft warm card shadow used throughout.
extension View {
    func ksCardShadow(strong: Bool = false) -> some View {
        shadow(
            color: Color(hex: 0x785032, alpha: strong ? 0.12 : 0.07),
            radius: strong ? 22 : 13,
            x: 0,
            y: strong ? 12 : 8
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
