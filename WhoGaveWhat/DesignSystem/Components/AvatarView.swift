import SwiftUI
import UIKit

struct AvatarView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 44
    var selected = false
    var imageData: Data?

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            } else {
                Text(initials)
                    .font(Font.app(size * 0.4, .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous))
        .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(color))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: 3).padding(-1.5)
                    .background(
                        RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius + 2, style: .continuous)
                            .stroke(color, lineWidth: 2).padding(-3.5))
            }
        }
    }
}
