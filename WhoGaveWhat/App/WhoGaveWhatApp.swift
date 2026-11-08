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
                    store: store, preferences: Self.makePreferences(), analytics: analytics,
                    haptics: haptics)
            })
        launch.start()
        _launch = State(initialValue: launch)
    }

    /// The app's preferences. In Debug, the empty journal of `KS_EMPTY_STORE=1` gets its own, emptied each
    /// launch, so "This is me" or a restored default currency there never changes the device's real ones.
    private static func makePreferences() -> UserDefaultsPreferencesGateway {
        #if DEBUG
            if LaunchFlags.opensEmptyStore {
                let suite = "pro.ziganshin.WhoGaveWhat.debug-empty-store"
                if let defaults = UserDefaults(suiteName: suite) {
                    defaults.removePersistentDomain(forName: suite)
                    return UserDefaultsPreferencesGateway(defaults: defaults)
                }
            }
        #endif
        return UserDefaultsPreferencesGateway()
    }

    /// Opens the persistent store, or in Debug builds the seeded in-memory one when a screenshot
    /// launch sets `KS_SAMPLE_DATA=1` and an empty in-memory one for `KS_EMPTY_STORE=1`, failing once
    /// when `KS_STORE_FAULT=open` (see `LaunchFault`).
    private static var storeOpener: () throws -> SwiftDataStore {
        #if DEBUG
            let open: () throws -> SwiftDataStore
            if LaunchFlags.value("KS_SAMPLE_DATA") == "1" {
                open = { try .makePreview() }
            } else if LaunchFlags.opensEmptyStore {
                open = { try SwiftDataStore(inMemory: true) }
            } else {
                open = { try .openPersistent(preferences: UserDefaultsPreferencesGateway()) }
            }
            return LaunchFault()?.wrapOpen(open) ?? open
        #else
            return { try .openPersistent(preferences: UserDefaultsPreferencesGateway()) }
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
