import SwiftUI

extension EnvironmentValues {
    /// The app's analytics gateway for views that have no composition root at hand, such as
    /// reusable sheets. Set once at the root; previews and tests keep the silent default.
    @Entry var analytics: AnalyticsGateway = NoopAnalyticsGateway()
}
