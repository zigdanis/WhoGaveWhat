import SwiftUI

/// Fills the available height like a plain container, but scrolls when the
/// content (large Dynamic Type, small screens) needs more room.
struct ScrollWhenTight<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }
}
