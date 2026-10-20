import Foundation

struct AddGiftDraft {
    var name = ""
    var emoji: String?
    var value: Int?
    var valueTouched = false
    /// The approximate price inferred from the name; it applies only while the value is untouched.
    var estimatedValue: Int?
    var fromID: String?
    var toID: String?
    var paidByYou = false
    var occasion: String? = "Just because"
    var date = AppDate.today
    var createdAt: Date?
    var aiEmoji: String?
}
