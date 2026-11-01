import SwiftUI

/// The small "You" chip that marks the person whose point of view the app takes.
struct YouBadge: View {
    var body: some View {
        Text("You")
            .font(Font.app(11, .semibold)).foregroundColor(Color.brand)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.receivedTint))
            .fixedSize()
    }
}
