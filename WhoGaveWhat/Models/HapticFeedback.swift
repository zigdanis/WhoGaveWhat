import Foundation

/// The few feedback patterns the app plays. Each names a moment's meaning, not a motor pattern.
enum HapticFeedback: Equatable, Sendable {
    case success
    case warning
    case error
    case selection
    case softImpact
}
