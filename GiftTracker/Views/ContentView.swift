import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            KS.bg.ignoresSafeArea()
            switch store.screen {
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .signin:
                SignInView()
                    .transition(.opacity)
            case .app:
                RootAppView()
                    .transition(.opacity)
            }
        }
        .foregroundColor(KS.ink)
        .animation(.easeInOut(duration: 0.25), value: store.screen)
        .preferredColorScheme(.light)
    }
}
