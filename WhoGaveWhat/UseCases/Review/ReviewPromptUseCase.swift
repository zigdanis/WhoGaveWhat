import Foundation

/// Tracks days of use and new gifts, and decides when the app asks for an App Store rating.
/// The decision rules live in `ReviewPromptPolicy`; this keeps the stored state and the session.
@MainActor
final class ReviewPromptUseCase {
    private let preferences: PreferencesGateway
    private let policy: ReviewPromptPolicy
    private let version: String
    private let isEnabled: Bool
    private let now: () -> Date
    private let calendar: Calendar
    /// A failed save or a deletion this session: not a moment to ask.
    private var hadSetbackThisSession = false
    private var requestedThisSession = false

    init(
        preferences: PreferencesGateway,
        policy: ReviewPromptPolicy = ReviewPromptPolicy(),
        version: String = ReviewPromptUseCase.bundleVersion,
        isEnabled: Bool = true,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.preferences = preferences
        self.policy = policy
        self.version = version
        self.isEnabled = isEnabled
        self.now = now
        self.calendar = calendar
    }

    nonisolated static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func appBecameActive() {
        update { policy.recordingActiveDay($0, now: now(), calendar: calendar) }
    }

    /// The app left the screen; the next foreground use is a new session.
    func appEnteredBackground() {
        hadSetbackThisSession = false
        requestedThisSession = false
    }

    func noteSetback() {
        hadSetbackThisSession = true
    }

    /// Counts a newly created gift and reports whether this is the moment to ask.
    func newGiftSaved(giftsCount: Int, peopleCount: Int) -> Bool {
        update { policy.recordingNewGift($0) }
        guard isEnabled, !hadSetbackThisSession, !requestedThisSession else { return false }
        return policy.shouldRequest(
            preferences.reviewPromptState, now: now(), version: version,
            giftsCount: giftsCount, peopleCount: peopleCount)
    }

    /// Records a request handed to the system and returns its analytics event.
    func recordRequest(giftsCount: Int, peopleCount: Int) -> AnalyticsEvent {
        requestedThisSession = true
        let date = now()
        update { policy.recordingRequest($0, now: date, version: version) }
        let state = preferences.reviewPromptState
        return .reviewPromptRequested(
            activeDays: state.activeDays,
            daysSinceFirstLaunch: policy.daysSinceFirstActive(state, now: date, calendar: calendar),
            giftsCount: giftsCount,
            peopleCount: peopleCount,
            requestNumber: state.requestCount)
    }

    private func update(_ change: (ReviewPromptState) -> ReviewPromptState) {
        preferences.setReviewPromptState(change(preferences.reviewPromptState))
    }
}
