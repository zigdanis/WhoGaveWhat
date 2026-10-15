import Foundation

/// Validation for emoji text produced by the on-device model.
enum GiftEmoji {
    private static let variationSelector: UInt32 = 0xFE0F
    private static let keycap: UInt32 = 0x20E3
    private static let zeroWidthJoiner: UInt32 = 0x200D

    /// The model's reply as a single emoji grapheme, or nil when it is empty, has more
    /// than one grapheme, or is not an emoji: letters, digits, `#` and `*` without a keycap,
    /// text-style symbols such as `™` without a variation selector, and lone skin-tone
    /// modifiers or regional indicators.
    static func validated(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first else { return nil }
        return isEmoji(character) ? trimmed : nil
    }

    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        guard let first = scalars.first else { return false }
        if isModifier(first) || isRegionalIndicator(first) {
            // Only a flag is allowed to start with a regional indicator.
            return scalars.count == 2 && isRegionalIndicator(first) && isRegionalIndicator(scalars[1])
        }
        let properties = first.properties
        guard properties.isEmoji else { return false }
        if properties.isEmojiPresentation { return true }
        guard scalars.count > 1 else { return false }

        let hasKeycap = scalars.contains { $0.value == keycap }
        if first.value < 0x80 { return hasKeycap }
        return hasKeycap
            || scalars.contains { $0.value == variationSelector || $0.value == zeroWidthJoiner }
            || scalars.dropFirst().contains { isModifier($0) }
    }

    private static func isModifier(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmojiModifier
    }

    private static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F1E6...0x1F1FF).contains(scalar.value)
    }
}
