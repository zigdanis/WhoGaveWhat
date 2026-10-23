import SwiftUI

struct ContentView: View {
    let composition: AppComposition

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            RootAppView(composition: composition)
        }
        // Set at the root so every screen and sheet sees the same short-window signal.
        .measuresCompactVerticalSpace()
        .overlay(alignment: .topLeading) {
            // Verification launches expose the applied scheme so the journey can
            // confirm a dark capture really is dark.
            if launchColorScheme != nil { AppearanceMarker() }
        }
        .foregroundColor(Color.textPrimary)
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
