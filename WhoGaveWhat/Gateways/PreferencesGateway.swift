@MainActor
protocol PreferencesGateway: AnyObject {
    var currencyCode: String { get }
    var selfPersonID: String? { get }
    var installID: String { get }
    func setCurrencyCode(_ currencyCode: String)
    func setSelfPersonID(_ id: String?)
    /// Person IDs recently picked in an Insights picker, newest first.
    func recentInsightsPicks(for slot: InsightsPickerSlot) -> [String]
    func setRecentInsightsPicks(_ ids: [String], for slot: InsightsPickerSlot)
    /// Days of use, new gifts and past requests that time the App Store rating request.
    var reviewPromptState: ReviewPromptState { get }
    func setReviewPromptState(_ state: ReviewPromptState)
}

extension PreferencesGateway {
    /// The currency new gifts start in. It never changes gifts that are already saved.
    var defaultCurrency: SupportedCurrency {
        SupportedCurrency(rawValue: currencyCode) ?? .usd
    }
}
