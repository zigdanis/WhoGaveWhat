import CoreSpotlight
import SwiftUI

@main
struct WhoGaveWhatApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var composition: AppComposition

    init() {
        // Monitoring starts before the store loads, so a failure there is already reported.
        let analytics = Monitoring.makeAnalytics(configuration: .current())
        _composition = State(
            initialValue: AppComposition(
                store: Self.launchStore, preferences: UserDefaultsPreferencesGateway(), analytics: analytics,
                haptics: UIKitHapticsGateway()))
    }

    /// The persistent store, or in Debug builds the seeded in-memory one when a screenshot
    /// launch sets `KS_SAMPLE_DATA=1`.
    private static var launchStore: SwiftDataStore {
        #if DEBUG
            if ProcessInfo.processInfo.environment["KS_SAMPLE_DATA"] == "1" {
                return .preview
            }
        #endif
        return .shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView(composition: composition)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    composition.continueAppDiscovery(activity)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                composition.sceneBecameActive()
                Task { await composition.appDiscovery.refresh() }
            case .background:
                composition.sceneEnteredBackground()
            default:
                composition.sceneBecameInactive()
            }
        }
    }
}
