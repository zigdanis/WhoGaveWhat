import Foundation

/// Where the monitoring keys come from and whether this launch may report at all.
///
/// Keys live in build settings (`POSTHOG_API_KEY`, `POSTHOG_HOST`, `SENTRY_DSN`) that the
/// Info.plist exposes; an empty value leaves that service off. Only launches on a real device
/// report; the Simulator and `KS_` verification launches stay silent. A Debug build on a device
/// reports too, tagged `debug`, so the integration can be checked from Xcode.
struct MonitoringConfiguration: Equatable {
    static let postHogAPIKeyInfoKey = "PostHogAPIKey"
    static let postHogHostInfoKey = "PostHogHost"
    static let sentryDSNInfoKey = "SentryDSN"
    static let defaultPostHogHost = "https://eu.i.posthog.com"

    var postHogAPIKey: String?
    var postHogHost: String
    var sentryDSN: String?
    var isDebugBuild: Bool
    var isSimulator: Bool
    var isVerificationLaunch: Bool
    var isTestFlight: Bool

    init(
        postHogAPIKey: String? = nil,
        postHogHost: String? = nil,
        sentryDSN: String? = nil,
        isDebugBuild: Bool,
        isSimulator: Bool,
        isVerificationLaunch: Bool,
        isTestFlight: Bool
    ) {
        self.postHogAPIKey = Self.nonEmpty(postHogAPIKey)
        self.postHogHost = Self.nonEmpty(postHogHost) ?? Self.defaultPostHogHost
        self.sentryDSN = Self.nonEmpty(sentryDSN)
        self.isDebugBuild = isDebugBuild
        self.isSimulator = isSimulator
        self.isVerificationLaunch = isVerificationLaunch
        self.isTestFlight = isTestFlight
    }

    /// Reads the keys from the main bundle and the build flags of this process.
    static func current(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        receiptURL: URL? = Bundle.main.appStoreReceiptURL
    ) -> MonitoringConfiguration {
        #if DEBUG
            let isDebugBuild = true
        #else
            let isDebugBuild = false
        #endif
        #if targetEnvironment(simulator)
            let isSimulator = true
        #else
            let isSimulator = false
        #endif
        return MonitoringConfiguration(
            postHogAPIKey: info[postHogAPIKeyInfoKey] as? String,
            postHogHost: info[postHogHostInfoKey] as? String,
            sentryDSN: info[sentryDSNInfoKey] as? String,
            isDebugBuild: isDebugBuild,
            isSimulator: isSimulator,
            isVerificationLaunch: isVerificationLaunch(launchEnvironment),
            isTestFlight: receiptURL?.lastPathComponent == "sandboxReceipt"
        )
    }

    /// Screenshot, smoke and UI-test launches set `KS_` variables; none of them is a real user.
    static func isVerificationLaunch(_ environment: [String: String]) -> Bool {
        environment.keys.contains { $0.hasPrefix("KS_") }
    }

    var isReportingAllowed: Bool {
        !isSimulator && !isVerificationLaunch
    }

    var isPostHogConfigured: Bool { postHogAPIKey != nil }
    var isSentryConfigured: Bool { sentryDSN != nil }

    /// The environment tag both services show.
    var environmentName: String {
        if isDebugBuild { return "debug" }
        return isTestFlight ? "testflight" : "appstore"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Builds the one analytics gateway the app uses from the configuration and the user's choice.
@MainActor
enum Monitoring {
    static func makeAnalytics(configuration: MonitoringConfiguration, isEnabled: Bool) -> AnalyticsGateway {
        var gateways: [AnalyticsGateway] = []
        if configuration.isDebugBuild {
            gateways.append(LoggingAnalyticsGateway())
        }
        if configuration.isReportingAllowed {
            // The crash reporter starts first so a failure while PostHog starts is still captured.
            if let dsn = configuration.sentryDSN {
                gateways.append(
                    SentryCrashReportingGateway(dsn: dsn, environment: configuration.environmentName, enabled: isEnabled))
            }
            if let apiKey = configuration.postHogAPIKey {
                gateways.append(
                    PostHogAnalyticsGateway(
                        apiKey: apiKey, host: configuration.postHogHost,
                        environment: configuration.environmentName, enabled: isEnabled))
            }
        }
        switch gateways.count {
        case 0: return NoopAnalyticsGateway()
        case 1: return gateways[0]
        default: return CompositeAnalyticsGateway(gateways)
        }
    }
}
