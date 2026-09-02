@MainActor
protocol PreferencesGateway: AnyObject {
    var didCompleteOnboarding: Bool { get }
    var currencyCode: String { get }
    func setDidCompleteOnboarding(_ completed: Bool)
    func setCurrencyCode(_ currencyCode: String)
}
