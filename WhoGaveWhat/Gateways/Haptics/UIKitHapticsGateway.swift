import UIKit

/// Plays feedback with UIKit's feedback generators. Imperative generators rather than SwiftUI's
/// `sensoryFeedback` so feedback still plays when its view disappears, such as a sheet that dismisses on save.
@MainActor
final class UIKitHapticsGateway: HapticsGateway {
    private var throttle = HapticThrottle()
    private let clock: () -> TimeInterval
    private lazy var notification = UINotificationFeedbackGenerator()
    private lazy var selection = UISelectionFeedbackGenerator()
    private lazy var softImpact = UIImpactFeedbackGenerator(style: .soft)

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    func play(_ feedback: HapticFeedback) {
        guard throttle.shouldPlay(feedback, at: clock()) else { return }
        switch feedback {
        case .success: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        case .error: notification.notificationOccurred(.error)
        case .selection: selection.selectionChanged()
        case .softImpact: softImpact.impactOccurred(intensity: 0.5)
        }
    }
}
