import Foundation

/// The one place the app asks for tactile feedback. Features and the composition root say what
/// happened; the gateway decides how it feels.
@MainActor
protocol HapticsGateway: AnyObject {
    func play(_ feedback: HapticFeedback)
}

/// The gateway for tests, previews and builds without haptics.
@MainActor
final class NoopHapticsGateway: HapticsGateway {
    nonisolated init() {}

    func play(_ feedback: HapticFeedback) {}
}
