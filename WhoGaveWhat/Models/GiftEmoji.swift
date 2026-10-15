import Foundation

/// Validation for emoji text produced by the on-device model.
enum GiftEmoji {
    /// The model's reply as a single emoji grapheme, or nil when it is empty, has more
    /// than one grapheme, or is plain text such as a letter, digit, `#` or `*`.
    static func validated(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first,
            let first = character.unicodeScalars.first
        else { return nil }
        let properties = first.properties
        // Digits, `#`, `*`, ©, and ® carry the Emoji property as keycap or text bases;
        // those need an explicit emoji presentation to count.
        guard properties.isEmojiPresentation || (properties.isEmoji && first.value > 0xFF) else {
            return nil
        }
        return trimmed
    }
}
