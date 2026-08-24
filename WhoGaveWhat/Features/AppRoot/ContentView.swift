import SwiftUI

struct ContentView: View {
    let composition: AppComposition

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            switch composition.router.screen {
            case .onboarding:
                OnboardingView(router: composition.router)
                    .transition(.opacity)
            case .signIn:
                SignInView(composition: composition)
                    .transition(.opacity)
            case .main:
                RootAppView(composition: composition)
                    .transition(.opacity)
            }
        }
        .foregroundColor(Color.ink)
        .animation(.easeInOut(duration: 0.25), value: composition.router.screen)
        .preferredColorScheme(.light)
    }
}
