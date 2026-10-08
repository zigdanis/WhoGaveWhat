import SwiftUI
import UIKit

struct AvatarView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 44
    var selected = false
    var imageData: Data?
    @State private var decodedImage: UIImage?

    var body: some View {
        Group {
            if let decodedImage {
                Image(uiImage: decodedImage).resizable().scaledToFill()
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
        .onAppear { updateImageCache() }
        .onChange(of: imageData) { _, _ in updateImageCache() }
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

    private func updateImageCache() {
        decodedImage = imageData.flatMap { UIImage(data: $0) }
    }
}
