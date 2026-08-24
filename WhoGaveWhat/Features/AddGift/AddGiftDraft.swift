import Foundation

struct AddGiftDraft {
    var name = ""
    var emoji: String?
    var value: Int?
    var valueTouched = false
    var fromID: String? = "you"
    var toID: String?
    var paidByYou = false
    var celebration: String? = "Just because"
    var date = AppDate.today
    var aiEmoji: String?
    var aiValue: Double?
}
