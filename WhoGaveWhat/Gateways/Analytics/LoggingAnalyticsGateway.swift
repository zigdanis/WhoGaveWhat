import OSLog

/// Writes every event and failure to the unified log, so instrumentation can be checked in
/// Console or with `log stream --predicate 'subsystem == "pro.ziganshin.WhoGaveWhat"'`.
@MainActor
final class LoggingAnalyticsGateway: AnalyticsGateway {
    private static let logger = Logger(subsystem: "pro.ziganshin.WhoGaveWhat", category: "Analytics")
    private var isEnabled = true

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        Self.logger.notice("event \(event.name, privacy: .public) \(Self.describe(event.properties), privacy: .public)")
    }

    func report(_ failure: AnalyticsFailure) {
        guard isEnabled else { return }
        let reason = failure.error.map { String(describing: $0) } ?? failure.message ?? ""
        Self.logger.error(
            "failure \(failure.operation, privacy: .public): \(reason, privacy: .public) \(Self.describe(failure.details), privacy: .public)")
    }

    func update(_ context: AnalyticsContext) {
        guard isEnabled else { return }
        Self.logger.notice("context \(Self.describe(context.properties), privacy: .public)")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        Self.logger.notice("analytics \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    private static func describe(_ properties: [String: AnalyticsValue]) -> String {
        properties.keys.sorted().map { key in
            switch properties[key] {
            case .string(let value): "\(key)=\(value)"
            case .int(let value): "\(key)=\(value)"
            case .bool(let value): "\(key)=\(value)"
            case nil: key
            }
        }.joined(separator: " ")
    }
}
