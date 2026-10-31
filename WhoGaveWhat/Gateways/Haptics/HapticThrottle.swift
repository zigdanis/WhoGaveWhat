import Foundation

/// Keeps quick repeats from turning into buzzing. Notifications always play; light ticks are
/// dropped, never queued, when another haptic played within `minimumInterval`.
struct HapticThrottle {
    var minimumInterval: TimeInterval = 0.12
    private var lastPlayed: TimeInterval?

    mutating func shouldPlay(_ feedback: HapticFeedback, at now: TimeInterval) -> Bool {
        switch feedback {
        case .success, .warning, .error:
            break
        case .selection, .softImpact:
            if let lastPlayed, now - lastPlayed < minimumInterval { return false }
        }
        lastPlayed = now
        return true
    }
}
