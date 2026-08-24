import SwiftUI

/// Who Gave What design tokens — ported from the Claude Design "Who Gave What"
/// + "Design System" handoff. A native Apple feel: San Francisco type, an
/// 8px square-edged radius, white cards on a #F2F2F7 grouped field, and a
/// black / white / emerald palette drawn from the app icon. `KS` = the app's
/// style namespace.
enum KS {
    // MARK: Brand palette (from the icon: ink + emerald)
    static let ink         = Color(hex: 0x12161C)   // primary text, given gifts, dark fills
    static let emerald     = Color(hex: 0x1FA971)   // switches "on", icon accent
    static let emeraldDeep = Color(hex: 0x12805C)   // links, selection, received

    // MARK: Semantic flow colors
    static let recv      = emeraldDeep              // Received accent
    static let recvDeep  = Color(hex: 0x0E6B4D)
    static let recvTint  = Color(hex: 0xE6F2EC)     // received icon wells
    static let give      = ink                      // Given accent
    static let giveDeep  = Color(hex: 0x000000)
    static let giveTint  = Color(hex: 0xEEF0F3)     // given icon wells
    static let iconWell  = Color(hex: 0xEEF0F3)     // gift-row icon well — neutral, direction-agnostic
    static let gold      = Color(hex: 0x5B6573)     // slate — neutral occasion bars

    // MARK: Surfaces
    static let bg        = Color(hex: 0xF2F2F7)      // grouped app background
    static let card      = Color.white              // cards & rows
    static let pageTop   = Color(hex: 0xEEF1F4)

    // MARK: Text shades
    static let muted     = Color(hex: 0x8A8F98)     // captions & metadata (secondary)
    static let muted2    = Color(hex: 0x6C7280)     // body secondary
    static let muted3    = Color(hex: 0x8A8F98)     // row subtitles
    static let muted4    = Color(hex: 0xAEB4BE)     // tertiary / meta
    static let placeholder = Color(hex: 0xAEB4BE)
    static let chevron   = Color(hex: 0xC5CAD2)
    static let chipText  = Color(hex: 0x5C6573)     // unselected segment label

    // MARK: Lines & tracks
    static let sep       = Color(red: 60/255, green: 60/255, blue: 67/255, opacity: 0.12) // hairline separators
    static let hairline  = sep                      // row dividers
    static let track     = Color(hex: 0xEFEFF1)     // bar / segmented backgrounds
    static let border    = Color(hex: 0xE1E6EC)     // field / chip borders (sign-in)

    /// One calm radius for cards, buttons, inputs, avatars and the icon glyph.
    static let radius: CGFloat = 8
    /// Modal sheets are the one exception — 14px on the top corners for the native lift.
    static let sheetRadius: CGFloat = 14

    /// Native San Francisco / system-ui — straight weight pass-through.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
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

/// Ruble formatting with thin-space grouping and a non-breaking space before ₽,
/// matching the prototype `fmt()`.
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
