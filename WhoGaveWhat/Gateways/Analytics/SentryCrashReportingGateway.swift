import Foundation
import Sentry

/// Crashes, hangs and handled failures through Sentry. Product events become breadcrumbs, so a
/// crash report shows the last steps before it; the app state travels as a context block.
@MainActor
final class SentryCrashReportingGateway: AnalyticsGateway {
    private let dsn: String
    private let environment: String
    private var context: AnalyticsContext?

    init(dsn: String, environment: String, enabled: Bool) {
        self.dsn = dsn
        self.environment = environment
        if enabled { start() }
    }

    private func start() {
        SentrySDK.start { [dsn, environment] options in
            options.dsn = dsn
            options.environment = environment
            options.enableAutoSessionTracking = true
            // No IP addresses, screenshots or view hierarchies: a report never shows user data.
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            // Automatic breadcrumbs record navigation titles, and a person screen is titled with
            // their name. Only the gateway's fixed product events become breadcrumbs.
            options.enableAutoBreadcrumbTracking = false
        }
        if let context { apply(context) }
    }

    func track(_ event: AnalyticsEvent) {
        let crumb = Breadcrumb(level: .info, category: "product")
        crumb.message = event.name
        for (key, value) in event.properties {
            crumb.setData(value: value.anyValue, key: key)
        }
        SentrySDK.addBreadcrumb(crumb)
    }

    func report(_ failure: AnalyticsFailure) {
        let configure: (Scope) -> Void = { scope in
            scope.setTag(value: failure.operation, key: "operation")
            if !failure.details.isEmpty { scope.setExtras(failure.details.anyValues) }
        }
        if let error = failure.error {
            SentrySDK.capture(error: Self.sanitized(error), block: configure)
        } else {
            SentrySDK.capture(message: "\(failure.operation): \(failure.message ?? "failed")", block: configure)
        }
    }

    func update(_ context: AnalyticsContext) {
        self.context = context
        apply(context)
    }

    /// Sentry copies an error's whole `userInfo` into the report, and a SwiftData or Foundation
    /// error can carry the failing record there, with a person's name or a gift title. Only the
    /// domain, code and Swift type travel; they are what groups and explains the failure.
    static func sanitized(_ error: Error) -> NSError {
        let nsError = error as NSError
        return NSError(
            domain: nsError.domain, code: nsError.code,
            userInfo: [NSLocalizedDescriptionKey: "\(nsError.domain) \(nsError.code) (\(type(of: error)))"])
    }

    private func apply(_ context: AnalyticsContext) {
        SentrySDK.configureScope { scope in
            scope.setContext(value: context.properties.anyValues, key: "app_state")
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, !SentrySDK.isEnabled {
            start()
        } else if !enabled, SentrySDK.isEnabled {
            SentrySDK.close()
        }
    }
}
