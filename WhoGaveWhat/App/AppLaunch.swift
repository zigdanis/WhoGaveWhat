import Foundation
import Observation

/// What the root shows: a short wait while the store opens, the app once it is open, or the reason
/// it could not open with a way to try again.
enum AppLaunchState {
    case opening
    case ready(AppComposition)
    case failed
}

/// Opens the store at launch and again on Retry. A store that cannot be opened (unavailable, damaged or
/// written by an unknown schema) is reported and left as it is: nothing here deletes, moves or recreates
/// the files, so a later attempt, or a later version of the app, still finds every record.
@MainActor
@Observable
final class AppLaunch {
    private(set) var state: AppLaunchState = .opening
    let analytics: AnalyticsGateway
    let haptics: HapticsGateway
    @ObservationIgnored private let openStore: () throws -> SwiftDataStore
    @ObservationIgnored private let makeComposition: (SwiftDataStore) -> AppComposition
    @ObservationIgnored private let retryPause: Duration
    @ObservationIgnored private var attempts = 0
    @ObservationIgnored private var isSceneActive = false

    /// `retryPause` keeps the wait on screen for a moment, so a Retry that fails again still reads as a new attempt.
    init(
        analytics: AnalyticsGateway,
        haptics: HapticsGateway,
        retryPause: Duration = .milliseconds(600),
        openStore: @escaping () throws -> SwiftDataStore,
        makeComposition: @escaping (SwiftDataStore) -> AppComposition
    ) {
        self.analytics = analytics
        self.haptics = haptics
        self.retryPause = retryPause
        self.openStore = openStore
        self.makeComposition = makeComposition
    }

    var composition: AppComposition? {
        if case .ready(let composition) = state { return composition }
        return nil
    }

    /// Opens the store right away, so a healthy launch shows the app on its first frame.
    func start() {
        guard attempts == 0 else { return }
        open()
    }

    /// The failure screen's Retry.
    func retry() async {
        guard case .failed = state else { return }
        state = .opening
        try? await Task.sleep(for: retryPause)
        open()
    }

    private func open() {
        attempts += 1
        let store: SwiftDataStore
        do {
            store = try openStore()
        } catch {
            analytics.report(
                AnalyticsFailure(operation: "open_store", error: error, details: ["attempt": .int(attempts)]))
            state = .failed
            return
        }
        let composition = makeComposition(store)
        state = .ready(composition)
        // After a Retry the scene is already in front; at launch it becomes active later.
        if isSceneActive { activate(composition) }
    }

    // MARK: - Scene phase, remembered while the store is not open

    func sceneBecameActive() {
        isSceneActive = true
        if let composition { activate(composition) }
    }

    func sceneBecameInactive() {
        isSceneActive = false
        composition?.sceneBecameInactive()
    }

    func sceneEnteredBackground() {
        isSceneActive = false
        composition?.sceneEnteredBackground()
    }

    private func activate(_ composition: AppComposition) {
        composition.sceneBecameActive()
        Task { await composition.appDiscovery.refresh() }
    }
}
