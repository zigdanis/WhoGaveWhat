import SwiftUI

struct Card<Content: View>: View {
    var corner: CGFloat = DesignMetrics.cornerRadius
    var strongShadow = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.card))
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .modifier(OptionalLift(on: strongShadow))
    }
}

private struct OptionalLift: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.ksCardShadow(strong: true) } else { content }
    }
}
