import Foundation

/// A handled problem worth a crash-reporting ticket: what the app was doing and what went wrong.
struct AnalyticsFailure {
    /// snake_case name of the operation, for example `save_gift`.
    let operation: String
    let error: Error?
    /// Describes failures without an `Error`, for example an unexpected HTTP status.
    let message: String?
    var details: [String: AnalyticsValue]

    init(operation: String, error: Error? = nil, message: String? = nil, details: [String: AnalyticsValue] = [:]) {
        self.operation = operation
        self.error = error
        self.message = message
        self.details = details
    }
}

/// Facts attached to every event and crash report: how much data the app holds and which
/// preferences are active. Counts and settings only, never the data itself.
struct AnalyticsContext: Equatable {
    var giftsCount: Int
    var peopleCount: Int
    var hasViewpoint: Bool
    var currency: String
    var cloudIcons: String

    var properties: [String: AnalyticsValue] {
        [
            "gifts_count": .int(giftsCount),
            "people_count": .int(peopleCount),
            "has_viewpoint": .bool(hasViewpoint),
            "currency": .string(currency),
            "cloud_icons": .string(cloudIcons)
        ]
    }
}

/// One sink for product events and handled failures. The app talks to a single gateway;
/// the composition root decides which services stand behind it.
@MainActor
protocol AnalyticsGateway: AnyObject {
    func track(_ event: AnalyticsEvent)
    func report(_ failure: AnalyticsFailure)
    func update(_ context: AnalyticsContext)
    /// Honors the user's choice in Settings. Nothing leaves the device while disabled.
    func setEnabled(_ enabled: Bool)
}

/// The gateway for tests, previews and builds without any monitoring service.
@MainActor
final class NoopAnalyticsGateway: AnalyticsGateway {
    nonisolated init() {}

    func track(_ event: AnalyticsEvent) {}
    func report(_ failure: AnalyticsFailure) {}
    func update(_ context: AnalyticsContext) {}
    func setEnabled(_ enabled: Bool) {}
}

extension AnalyticsValue {
    /// The value as the SDKs accept it.
    var anyValue: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .bool(let value): value
        }
    }
}

extension Dictionary where Key == String, Value == AnalyticsValue {
    var anyValues: [String: Any] {
        mapValues(\.anyValue)
    }
}
