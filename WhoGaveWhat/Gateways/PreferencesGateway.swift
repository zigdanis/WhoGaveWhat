@MainActor
protocol PreferencesGateway: AnyObject {
    var didCompleteOnboarding: Bool { get }
    func setDidCompleteOnboarding(_ completed: Bool)
}
