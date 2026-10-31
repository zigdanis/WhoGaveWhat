import Foundation

/// The few feedback patterns the app plays. Each names a moment's meaning, not a motor pattern.
enum HapticFeedback: Equatable, Sendable {
    case success
    case warning
    case error
    case selection
    case softImpact

    /// The feedback for the person editor's error alert, matching the message `PersonEditorSheet`
    /// shows: a duplicate name is the user's to fix, anything else is a failure.
    @MainActor
    static func personSaveFailure(_ error: Error) -> HapticFeedback {
        switch error {
        case PersonUpdateError.duplicateName: .warning
        default: .error
        }
    }
}
