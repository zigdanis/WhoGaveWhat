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
