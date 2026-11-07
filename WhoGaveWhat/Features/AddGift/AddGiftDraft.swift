import Foundation

struct AddGiftDraft: Equatable {
    var name = ""
    var emoji: String?
    var value: Int?
    var valueTouched = false
    /// The approximate price inferred from the name; it applies only while the value is untouched.
    var estimatedValue: Int?
    /// The currency `estimatedValue` was asked for, which the gift keeps when it is saved with it.
    var estimatedCurrency: SupportedCurrency?
    /// The currency of the gift's value. A new gift starts in the default currency.
    var currency: SupportedCurrency = .usd
    var fromID: String?
    var toID: String?
    var paidByYou = false
    var occasion: String? = "Just because"
    var date = AppDate.today
    var createdAt: Date?
    var aiEmoji: String?
}
