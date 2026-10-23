enum CloudIconConsent: String, Sendable {
    case undecided
    case allowed
    case declined
}

@MainActor
protocol PreferencesGateway: AnyObject {
    var currencyCode: String { get }
    var selfPersonID: String? { get }
    var cloudIconConsent: CloudIconConsent { get }
    var installID: String { get }
    func setCurrencyCode(_ currencyCode: String)
    func setSelfPersonID(_ id: String?)
    func setCloudIconConsent(_ consent: CloudIconConsent)
    /// Person IDs recently picked in an Insights picker, newest first.
    func recentInsightsPicks(for slot: InsightsPickerSlot) -> [String]
    func setRecentInsightsPicks(_ ids: [String], for slot: InsightsPickerSlot)
}
