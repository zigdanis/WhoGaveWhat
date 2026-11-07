import CoreSpotlight
import SwiftUI

@main
struct WhoGaveWhatApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var launch: AppLaunch

    init() {
        // Monitoring starts before the store opens, so a failure there is already reported.
        let analytics = Monitoring.makeAnalytics(configuration: .current())
        let haptics = UIKitHapticsGateway()
        let launch = AppLaunch(
            analytics: analytics, haptics: haptics, openStore: Self.storeOpener,
            makeComposition: { store in
                AppComposition(
                    store: store, preferences: UserDefaultsPreferencesGateway(), analytics: analytics,
                    haptics: haptics)
            })
        launch.start()
        _launch = State(initialValue: launch)
    }

    /// Opens the persistent store, or in Debug builds the seeded in-memory one when a screenshot
    /// launch sets `KS_SAMPLE_DATA=1`, failing once when `KS_STORE_FAULT=open` (see `LaunchFault`).
    private static var storeOpener: () throws -> SwiftDataStore {
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            let open: () throws -> SwiftDataStore =
                environment["KS_SAMPLE_DATA"] == "1" ? { try .makePreview() } : { try .openPersistent() }
            return LaunchFault()?.wrapOpen(open) ?? open
        #else
            return { try .openPersistent() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(launch: launch)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    // Without an open store the activity has nothing to keep; the app is already in front.
                    _ = launch.composition?.continueAppDiscovery(activity)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                launch.sceneBecameActive()
            case .background:
                launch.sceneEnteredBackground()
            default:
                launch.sceneBecameInactive()
            }
        }
    }
}
