import SwiftUI

/// The root: the app once its store is open, otherwise the wait or the failure with Retry.
struct ContentView: View {
    let launch: AppLaunch

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            switch launch.state {
            case .ready(let composition):
                RootAppView(composition: composition)
                    // The tab screens have no text fields; only sheets do, and they get their own keyboard inset.
                    // A sheet dismissed with the keyboard up in landscape on iPad can leave a stale keyboard inset
                    // on the other tabs, which then end their background at the keyboard's top edge.
                    .ignoresSafeArea(.keyboard)
            case .opening:
                StoreOpeningView()
            case .failed:
                StoreUnavailableView {
                    Task { await launch.retry() }
                }
            }
        }
        // Set at the root so every screen and sheet sees the same short-window signal.
        .measuresCompactVerticalSpace()
        .measuresAdaptiveLayout()
        .overlay(alignment: .topLeading) {
            // Verification launches expose the applied scheme so the journey can
            // confirm a dark capture really is dark.
            if launchColorScheme != nil { AppearanceMarker() }
        }
        .foregroundColor(Color.textPrimary)
        .preferredColorScheme(launchColorScheme)
        .environment(\.analytics, launch.analytics)
        .environment(\.haptics, launch.haptics)
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

private struct AppearanceMarker: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "Appearance"))
            .accessibilityIdentifier(colorScheme == .dark ? "appearance.dark" : "appearance.light")
    }
}
