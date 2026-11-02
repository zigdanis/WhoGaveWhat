import Foundation
import PostHog

/// Product analytics through PostHog. Events carry only the categories and counts in
/// `AnalyticsEvent`; the SDK adds its anonymous ID, device model and OS version, and its own
/// "Application Opened / Backgrounded / Installed / Updated" lifecycle events.
@MainActor
final class PostHogAnalyticsGateway: AnalyticsGateway {
    init(apiKey: String, host: String, environment: String) {
        let config = PostHogConfig(projectToken: apiKey, host: host)
        config.captureApplicationLifecycleEvents = true
        // SwiftUI screens are reported as explicit events instead of view-controller names.
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.sessionReplay = false
        // Feature flags are not used, so the app never calls the flags endpoint.
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        PostHogSDK.shared.setup(config)
        // The SDK keeps an opt-out from the Settings switch of earlier versions; that switch is gone.
        if PostHogSDK.shared.isOptOut() { PostHogSDK.shared.optIn() }
        PostHogSDK.shared.register(["app_environment": environment])
    }

    func track(_ event: AnalyticsEvent) {
        PostHogSDK.shared.capture(event.name, properties: event.properties.anyValues)
    }

    /// Failures go to the crash reporter; PostHog keeps the product picture only.
    func report(_ failure: AnalyticsFailure) {}

    func update(_ context: AnalyticsContext) {
        PostHogSDK.shared.register(context.properties.anyValues)
    }
}
