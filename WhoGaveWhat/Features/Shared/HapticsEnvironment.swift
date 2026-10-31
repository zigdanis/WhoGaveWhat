import SwiftUI

extension EnvironmentValues {
    /// The app's haptics gateway for views that have no composition root at hand, such as
    /// reusable controls and sheets. Set once at the root; previews and tests stay silent.
    @Entry var haptics: HapticsGateway = NoopHapticsGateway()
}
