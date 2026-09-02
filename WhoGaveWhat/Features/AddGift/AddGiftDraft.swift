import Foundation

struct AddGiftDraft {
    var name = ""
    var emoji: String?
    var value: Int?
    var valueTouched = false
    var fromID: String?
    var toID: String?
    var paidByYou = false
    var occasion: String? = "Just because"
    var date = AppDate.today
    var createdAt: Date?
    var aiEmoji: String?
    var aiValue: Double?
}
