import CoreSpotlight
import SwiftUI

@main
struct WhoGaveWhatApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var composition: AppComposition

    init() {
        _composition = State(initialValue: AppComposition(store: .shared))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(composition: composition)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    composition.continueAppDiscovery(activity)
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await composition.appDiscovery.refresh() }
            }
        }
    }
}
