import SwiftUI

struct AvatarView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 44
    var selected = false

    var body: some View {
        Text(initials)
            .font(Font.app(size * 0.4, .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(color))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                        .stroke(Color.white, lineWidth: 3).padding(-1.5)
                        .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius + 2, style: .continuous)
                            .stroke(color, lineWidth: 2).padding(-3.5))
                }
            }
    }
}
