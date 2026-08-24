@MainActor
struct CompleteOnboardingUseCase {
    let preferencesGateway: PreferencesGateway

    func execute() {
        preferencesGateway.setDidCompleteOnboarding(true)
    }
}
