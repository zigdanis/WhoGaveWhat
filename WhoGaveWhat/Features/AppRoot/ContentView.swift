import SwiftUI

struct ContentView: View {
    let composition: AppComposition

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            switch composition.router.screen {
            case .onboarding:
                OnboardingView(
                    router: composition.router,
                    currencyCode: composition.currencyCode
                )
                .transition(.opacity)
            case .signIn:
                SignInView(composition: composition)
                    .transition(.opacity)
            case .main:
                RootAppView(composition: composition)
                    .transition(.opacity)
            }
        }
        .foregroundColor(Color.textPrimary)
        .animation(.easeInOut(duration: 0.25), value: composition.router.screen)
        .preferredColorScheme(launchColorScheme)
    }

    /// Follows the system unless a verification launch sets `KS_APPEARANCE=dark|light`.
    private var launchColorScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["KS_APPEARANCE"] {
        case "dark": ColorScheme.dark
        case "light": ColorScheme.light
        default: nil
        }
    }
}
